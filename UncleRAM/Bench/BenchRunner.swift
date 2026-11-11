import Foundation
import Observation
import os
import StoreKit

/// 試作の合格条件を測る計測。ラウンドを自動で続けて、解放の時間・落ちたフレーム・使用量・スワップを記録する。
///
/// docs/SPEC.md「公開後の確認と試作の合格条件」:
/// - 100 ラウンド続けて強制終了が 0 回（最後まで記録が書き出されれば 0 回）
/// - 最高速でも 60fps を保つ
/// - メモリの解放が 200ms 以内
/// - Mac でスワップが増えない。App Sandbox を有効にしても host_statistics64 の値が取れる
/// - ページごとに少しだけ乱数を書く方式（sparse）でも使用量に計上されるか（圧縮されないか）
///
/// 起動引数 `-bench <ラウンド数>`（と `-bench-fill full|sparse`）で、起動してすぐに始める。
/// 画面の「計測」ボタンは、Debug ビルドと TestFlight（App Store 以外）のときだけ出す。
@MainActor
@Observable
final class BenchRunner {
    struct RoundRecord: Codable, Equatable {
        var index: Int
        var outcome: String
        var budgetMegabytes: Double
        var targetFill: Double
        var donatedMegabytes: Double
        var releaseMilliseconds: Double
        var peakFootprintMegabytes: Double?
        var footprintAfterReleaseMegabytes: Double?
        /// ピークのときの、使用量の増えた分 ÷ 献上量（1 に近いほど、書いた分が使用量に計上されている）
        var footprintPerDonated: Double?
        /// ピークのときの、このアプリの圧縮されている量
        var peakCompressedMegabytes: Double?
        /// 献上中のフレーム
        var frames: FrameMonitor.Stats
        /// 離してから結果が出るまで（全解放の間）のフレーム
        var releaseFrames: FrameMonitor.Stats
    }

    struct Summary: Codable, Equatable {
        var device: String
        var osVersion: String
        var fillMode: Allocator.FillMode
        var plannedRounds: Int
        var completedRounds: Int
        var outcomes: [String: Int]
        var maxReleaseMilliseconds: Double
        var p95ReleaseMilliseconds: Double
        var releasesOver200Milliseconds: Int
        var totalFrames: Int
        var droppedFrames: Int
        var worstFrameIntervalMilliseconds: Double
        /// 離してから結果が出るまでの、落ちたフレームと最長の間隔
        var releaseDroppedFrames: Int
        var releaseWorstFrameIntervalMilliseconds: Double
        var minimumFootprintPerDonated: Double?
        var swapBeforeMegabytes: Double?
        var swapMaxMegabytes: Double?
        var hostStatisticsAvailable: Bool
        var memoryWarnings: Int
        var startedAt: Date
        var finishedAt: Date?
        var rounds: [RoundRecord]
    }

    private(set) var isRunning = false
    private(set) var progress = 0
    private(set) var plannedRounds = 0
    private(set) var summary: Summary?
    private(set) var savedURL: URL?
    /// 計測のボタンを出すか（Debug ビルドと、App Store 以外の配布）
    private(set) var isAvailable = false

    @ObservationIgnored private let engine: RoundEngine
    @ObservationIgnored private let frameMonitor = FrameMonitor()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "jp.shilokuma.UncleRAM", category: "Bench")

    init(engine: RoundEngine) {
        self.engine = engine
        #if DEBUG
        isAvailable = true
        #else
        Task { [weak self] in
            let environment = try? await AppTransaction.shared.payloadValue.environment
            self?.isAvailable = environment != nil && environment != .production
        }
        #endif
    }

    /// 起動引数で頼まれていれば始める
    func startFromLaunchArgumentsIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-bench"), arguments.indices.contains(index + 1),
              let rounds = Int(arguments[index + 1]), rounds > 0, !isRunning else {
            return
        }
        var fillMode = Allocator.FillMode.full
        if let fillIndex = arguments.firstIndex(of: "-bench-fill"), arguments.indices.contains(fillIndex + 1),
           let mode = Allocator.FillMode(rawValue: arguments[fillIndex + 1]) {
            fillMode = mode
        }
        isAvailable = true
        start(rounds: rounds, fillMode: fillMode)
    }

    func start(rounds: Int = 100, fillMode: Allocator.FillMode = .full) {
        guard !isRunning else {
            return
        }
        isRunning = true
        progress = 0
        plannedRounds = rounds
        savedURL = nil
        engine.allocator.fillMode = fillMode
        task = Task { [weak self] in
            await self?.run(rounds: rounds, fillMode: fillMode)
        }
    }

    func cancel() {
        task?.cancel()
    }

    func dismissSummary() {
        summary = nil
    }

    private func run(rounds: Int, fillMode: Allocator.FillMode) async {
        let warningsBefore = engine.memoryWarningCount
        var summary = Self.emptySummary(rounds: rounds, fillMode: fillMode)
        var swapMax = ProcessMemory.swapUsedBytes()
        var random = SplitMix64.randomlySeeded()

        for index in 1...rounds {
            guard !Task.isCancelled else {
                break
            }
            if case .result = engine.phase {
                engine.reset()
            }
            try? await Task.sleep(for: .milliseconds(400))
            engine.refreshBudget()
            guard engine.phase == .ready else {
                logger.error("ラウンド \(index) を始められません: \(String(describing: self.engine.phase))")
                break
            }
            // 離す位置を散らす（早いもの・回収ラインを越えるもの・安全ラインまで押すもの）
            let record = await playRound(index: index, target: random.uniform(0.2...0.86), swapMax: &swapMax)
            summary.rounds.append(record)
            summary.completedRounds = index
            progress = index
            logger.info("ラウンド \(index): \(record.outcome) \(record.donatedMegabytes) MB 解放 \(record.releaseMilliseconds) ms")
        }

        summary.swapMaxMegabytes = swapMax.map(Self.megabytes)
        summary.memoryWarnings = engine.memoryWarningCount - warningsBefore
        summary.finishedAt = Date()
        Self.aggregate(&summary)
        self.summary = summary
        savedURL = save(summary)
        if case .result = engine.phase {
            engine.reset()
        }
        isRunning = false
    }

    /// 1 ラウンドを、献上量が target（枠に対する割合）に届くまで押し続けて遊ぶ
    private func playRound(index: Int, target: Double, swapMax: inout UInt64?) async -> RoundRecord {
        let baseline = ProcessMemory.footprintBytes()
        frameMonitor.start()
        engine.beginHold()
        var peakFootprint = baseline
        var peakCompressed = ProcessMemory.compressedBytes()
        var peakDonated: UInt64 = 0
        while engine.phase == .donating, engine.donatedFill < target, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            if let footprint = ProcessMemory.footprintBytes(), footprint > (peakFootprint ?? 0) {
                peakFootprint = footprint
                peakDonated = engine.donatedBytes
            }
            if let compressed = ProcessMemory.compressedBytes(), compressed > (peakCompressed ?? 0) {
                peakCompressed = compressed
            }
            if let swap = ProcessMemory.swapUsedBytes(), swap > (swapMax ?? 0) {
                swapMax = swap
            }
        }
        frameMonitor.markRelease()
        engine.endHold(.released)
        let outcome = await engine.waitForResult()
        // 結果の画面に切り替わる 1 フレーム分も含めて数える
        try? await Task.sleep(for: .milliseconds(100))
        frameMonitor.stop()
        return RoundRecord(
            index: index,
            outcome: outcome.map(Self.describe) ?? "none",
            budgetMegabytes: Self.megabytes(engine.budgetBytes),
            targetFill: target,
            donatedMegabytes: Self.megabytes(outcome?.donatedBytes ?? 0),
            releaseMilliseconds: (engine.lastReleaseDuration ?? 0) * 1000,
            peakFootprintMegabytes: peakFootprint.map(Self.megabytes),
            footprintAfterReleaseMegabytes: ProcessMemory.footprintBytes().map(Self.megabytes),
            footprintPerDonated: Self.ratio(peak: peakFootprint, baseline: baseline, donated: peakDonated),
            peakCompressedMegabytes: peakCompressed.map(Self.megabytes),
            frames: frameMonitor.stats,
            releaseFrames: frameMonitor.releaseStats
        )
    }

    private static func emptySummary(rounds: Int, fillMode: Allocator.FillMode) -> Summary {
        Summary(
            device: DeviceDescription.current,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            fillMode: fillMode,
            plannedRounds: rounds,
            completedRounds: 0,
            outcomes: [:],
            maxReleaseMilliseconds: 0,
            p95ReleaseMilliseconds: 0,
            releasesOver200Milliseconds: 0,
            totalFrames: 0,
            droppedFrames: 0,
            worstFrameIntervalMilliseconds: 0,
            releaseDroppedFrames: 0,
            releaseWorstFrameIntervalMilliseconds: 0,
            swapBeforeMegabytes: ProcessMemory.swapUsedBytes().map(megabytes),
            swapMaxMegabytes: nil,
            hostStatisticsAvailable: HostMemory.statistics() != nil,
            memoryWarnings: 0,
            startedAt: Date(),
            rounds: []
        )
    }

    private static func aggregate(_ summary: inout Summary) {
        let releases = summary.rounds.map(\.releaseMilliseconds).sorted()
        summary.maxReleaseMilliseconds = releases.last ?? 0
        let p95Index = min(releases.count - 1, Int(Double(releases.count) * 0.95))
        summary.p95ReleaseMilliseconds = releases.isEmpty ? 0 : releases[p95Index]
        summary.releasesOver200Milliseconds = releases.filter { $0 > 200 }.count
        summary.totalFrames = summary.rounds.map(\.frames.frames).reduce(0, +)
        summary.droppedFrames = summary.rounds.map(\.frames.droppedFrames).reduce(0, +)
        summary.worstFrameIntervalMilliseconds = summary.rounds.map(\.frames.worstIntervalMilliseconds).max() ?? 0
        summary.releaseDroppedFrames = summary.rounds.map(\.releaseFrames.droppedFrames).reduce(0, +)
        summary.releaseWorstFrameIntervalMilliseconds = summary.rounds.map(\.releaseFrames.worstIntervalMilliseconds).max() ?? 0
        summary.minimumFootprintPerDonated = summary.rounds.compactMap(\.footprintPerDonated).min()
        summary.outcomes = Dictionary(grouping: summary.rounds, by: \.outcome).mapValues(\.count)
    }

    private func save(_ summary: Summary) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(summary),
              let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let stamp = ISO8601DateFormatter().string(from: summary.startedAt).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("bench-\(summary.fillMode.rawValue)-\(stamp).json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url)
            logger.info("計測の結果を書き出しました: \(url.path, privacy: .public)")
            return url
        } catch {
            logger.error("計測の結果を書き出せません: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 結果を JSON の文字列にする（画面からコピーする用）
    func summaryJSON() -> String? {
        guard let summary else {
            return nil
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(summary)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func describe(_ outcome: RoundOutcome) -> String {
        switch outcome.kind {
        case .delivered:
            outcome.stoppedAtSafetyLine ? "safetyLine" : "delivered"
        case .collected:
            outcome.plan.isEarlyCollection ? "earlyCollected" : "collected"
        case .audited:
            "audited"
        case let .voided(reason):
            "voided-\(reason)"
        }
    }

    private static func megabytes(_ bytes: UInt64) -> Double {
        (Double(bytes) / 1_048_576 * 10).rounded() / 10
    }

    private static func ratio(peak: UInt64?, baseline: UInt64?, donated: UInt64) -> Double? {
        guard let peak, let baseline, donated > 0, peak > baseline else {
            return nil
        }
        return (Double(peak - baseline) / Double(donated) * 1000).rounded() / 1000
    }
}

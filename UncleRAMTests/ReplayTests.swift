import AVFoundation
import Foundation
import SwiftUI
import Testing
@testable import UncleRAM

/// リプレイ動画（docs/SPEC.md「共有機能」の動画）。記録の間引き・動画の長さと速さ・デイリーで回収ラインを出さないこと・
/// 書き出した動画の長さと大きさと音を確かめる
@MainActor
@Suite(.serialized)
struct ReplayTests {
    private static let megabyte: UInt64 = 1_048_576

    private static func plan(line: Double, early: Bool = false) -> RoundPlan {
        RoundPlan(isEarlyCollection: early, collectionLine: line, hintThresholds: [line - 0.15, line - 0.08, line - 0.02], bluffAt: nil)
    }

    private static func outcome(_ kind: RoundOutcome.Kind, released: Double, line: Double) -> RoundOutcome {
        let budget = 4_096 * megabyte
        return RoundOutcome(
            kind: kind,
            plan: plan(line: line),
            budgetBytes: budget,
            donatedBytes: UInt64(Double(budget) * released),
            stoppedAtSafetyLine: false
        )
    }

    /// 公称の速さで `released` まで押したリプレイ（ヒントは回収ラインの手前 15%・8%・2%）
    private static func replay(_ kind: RoundOutcome.Kind, released: Double, line: Double) throws -> RoundReplay {
        try #require(RoundReplay.demo(outcome: outcome(kind, released: released, line: line), safetyLineFill: 0.85))
    }

    private static let daily = ShareSummary.Mode(daily: DailyChallenge(day: DailyDay(year: 2026, month: 12, day: 12)))

    private static func timeline(_ kind: RoundOutcome.Kind, released: Double, line: Double) throws -> ReplayTimeline {
        ReplayTimeline(script: ReplayScript(replay: try replay(kind, released: released, line: line), mode: .express))
    }

    // MARK: - 記録

    /// 献上量は 0.1 秒ごとに残し、それより短い間隔の点は捨てる。段階とはったりは、変わったときだけ残す
    @Test
    func recordingKeepsSamplesAtIntervalAndChangesOnly() {
        var recording = RoundRecording(budgetBytes: 1 << 32, safetyLineFill: 0.85, isPractice: false)
        recording.record(fill: 0, at: 0)
        recording.record(fill: 0.004, at: 0.04)
        recording.record(fill: 0.01, at: 0.1)
        recording.record(fill: 0.02, at: 0.2)
        #expect(recording.samples.map(\.time) == [0, 0.1, 0.2])

        recording.record(stage: .none, at: 0)
        recording.record(stage: .sign, at: 1)
        recording.record(stage: .sign, at: 1.1)
        recording.record(stage: .approach, at: 2)
        #expect(recording.stageChanges.map(\.stage) == [.sign, .approach])

        recording.record(bluff: .showing, at: 0.5)
        recording.record(bluff: .showing, at: 0.6)
        recording.record(bluff: .grinning, at: 1.5)
        recording.record(bluff: .none, at: 2.3)
        #expect(recording.bluffChanges.map(\.bluff) == [.showing, .grinning, .none])
    }

    /// 長く押し続けても、点が上限を越えたら 1 つおきに間引いて間隔を倍にする。最初と最後の点は残り、記録は数 KB に収まる
    @Test
    func recordingThinsLongRounds() {
        var recording = RoundRecording(budgetBytes: 1 << 32, safetyLineFill: 0.85, isPractice: false)
        for step in 0...3_000 {
            let time = Double(step) * RoundRecording.sampleInterval
            recording.record(fill: min(0.85, time / 400), at: time)
        }
        recording.finish(fill: 0.75, at: 300.05)
        #expect(recording.samples.count <= RoundRecording.maximumSamples)
        #expect(recording.samples.count > RoundRecording.maximumSamples / 2)
        #expect(recording.samples.first?.time == 0)
        #expect(recording.samples.last == RoundRecording.Sample(time: 300.05, fill: 0.75))
        #expect(recording.interval > RoundRecording.sampleInterval)
        #expect(recording.byteCount <= 4_096)
        // 時刻は増える一方で、離した量を越える点は無い
        let times = recording.samples.map(\.time)
        #expect(times == times.sorted())
        #expect(recording.samples.allSatisfy { $0.fill <= 0.75 })

        // ふつうのラウンド（11 秒ほど）は間引かずに収まる
        var short = RoundRecording(budgetBytes: 1 << 32, safetyLineFill: 0.85, isPractice: false)
        for step in 0...110 {
            short.record(fill: Double(step) / 130, at: Double(step) * RoundRecording.sampleInterval)
        }
        #expect(short.samples.count == 111)
        #expect(short.interval == RoundRecording.sampleInterval)
        #expect(short.byteCount < 1_024)
    }

    /// 結果のリプレイは、離した瞬間の量を最後の点にする。無効になったラウンドはリプレイを作らない
    @Test
    func replayEndsAtReleasedFill() throws {
        var recording = RoundRecording(budgetBytes: 4_096 * Self.megabyte, safetyLineFill: 0.85, isPractice: false)
        recording.record(fill: 0, at: 0)
        recording.record(fill: 0.1, at: 0.1)
        recording.record(fill: 0.2, at: 0.2)
        let delivered = Self.outcome(.delivered, released: 0.25, line: 0.6)
        let replay = try #require(RoundReplay(recording: recording, duration: 0.25, outcome: delivered))
        #expect(replay.recording.samples.last == RoundRecording.Sample(time: 0.25, fill: 0.25))
        #expect(replay.result == .delivered)
        let voided = Self.outcome(.voided(.background), released: 0.25, line: 0.6)
        #expect(RoundReplay(recording: recording, duration: 0.25, outcome: voided) == nil)
    }

    /// 記録の係は、RoundScreen と同じく engine の段階を受け取って、献上中の量を 0.1 秒ごとに読む。計測中は記録しない
    @Test
    func recorderReadsEngineWithoutTouchingDonation() async throws {
        let engine = RoundEngine(
            allocator: Allocator(fillMode: .sparse),
            probe: SimulatedMemoryProbe(totalBytes: 2_048 * Self.megabyte),
            random: SplitMix64(seed: 3),
            thermalState: { .nominal }
        )
        let recorder = RoundReplayRecorder()
        engine.beginHold()
        recorder.phaseChanged(to: engine.phase, engine: engine)
        try await Task.sleep(for: .milliseconds(450))
        engine.endHold(.released)
        recorder.phaseChanged(to: engine.phase, engine: engine)
        let outcome = try #require(await engine.waitForResult())
        recorder.phaseChanged(to: engine.phase, engine: engine)
        let replay = try #require(recorder.replay)
        #expect(replay.recording.samples.count >= 3)
        #expect(replay.recording.samples.last?.fill == Float(outcome.releasedFill))
        #expect(replay.duration > 0.3)
        #expect(engine.allocator.allocatedBytes == 0)

        // 次のラウンドに進むと消える。計測（isAutomated）のラウンドは記録しない
        engine.reset()
        recorder.phaseChanged(to: engine.phase, engine: engine)
        #expect(recorder.replay == nil)
        engine.isAutomated = true
        engine.beginHold()
        recorder.phaseChanged(to: engine.phase, engine: engine)
        try await Task.sleep(for: .milliseconds(150))
        engine.endHold(.released)
        recorder.phaseChanged(to: engine.phase, engine: engine)
        _ = await engine.waitForResult()
        recorder.phaseChanged(to: engine.phase, engine: engine)
        #expect(recorder.replay == nil)
    }

    // MARK: - 長さと速さ

    /// 献上の部分は少なくとも 1.25 倍に速め、6 秒を越えるときは 6 秒に収める。動画はどのラウンドでも 10 秒ほどまでに収まる
    @Test(arguments: [0.3, 3.0, 6.0, 7.5, 10.1, 30.0])
    func timelineSpeedsUpToFitAboutTenSeconds(duration: Double) throws {
        let curve = DonationCurve.nominal(until: 0.5)
        var recording = RoundRecording(budgetBytes: 1 << 32, safetyLineFill: 0.85, isPractice: false)
        for point in curve.points {
            recording.record(fill: point.fill, at: point.time * duration / curve.duration)
        }
        let outcome = Self.outcome(.delivered, released: 0.5, line: 0.7)
        let replay = try #require(RoundReplay(recording: recording, duration: duration, outcome: outcome))
        let timeline = ReplayTimeline(script: ReplayScript(replay: replay, mode: .express))
        #expect(timeline.speed >= ReplayTimeline.minimumSpeed)
        #expect(abs(timeline.replayDuration - min(duration / ReplayTimeline.minimumSpeed, ReplayTimeline.targetReplayDuration)) < 1e-9)
        #expect(timeline.totalDuration <= 10.3)
        #expect(timeline.frameCount == Int((timeline.totalDuration * 30).rounded(.up)))
        // 最後の 2 秒は明細書
        #expect(timeline.frame(at: timeline.frameCount - 1).endCardOpacity == 1)
        #expect(timeline.frame(at: 0).scene == .waiting)
    }

    /// ふつうのラウンド（公称の速さで回収ラインの手前まで、7〜10 秒）は、動画が 9〜10 秒ほどになる
    @Test
    func typicalRoundMakesAboutTenSecondVideo() throws {
        let timeline = ReplayTimeline(script: ReplayScript(replay: try Self.replay(.delivered, released: 0.62, line: 0.64), mode: .express))
        #expect(timeline.totalDuration > 9)
        #expect(timeline.totalDuration <= 10.3)
        #expect(timeline.speed > ReplayTimeline.minimumSpeed)
    }

    // MARK: - 速達便とデイリーの出し分け

    /// 速達便は記録どおりの量と枠を出し、最後に回収ラインを明かす
    @Test
    func expressScriptRevealsLineAtResult() throws {
        let replay = try Self.replay(.delivered, released: 0.62, line: 0.64)
        let script = ReplayScript(replay: replay, mode: .express)
        #expect(script.revealedLine == 0.64)
        #expect(script.budgetBytes == 4_096 * Self.megabyte)
        #expect(script.donatedBytes == replay.donatedBytes)
        #expect(script.squares == nil)
        let timeline = ReplayTimeline(script: script)
        let result = timeline.frame(at: Int(timeline.resultStart * 30) + 10)
        #expect(result.scene == .result)
        #expect(result.fill == replay.releasedFill)
        #expect(result.donatedBytes == replay.donatedBytes)
    }

    /// デイリーは回収ラインの位置を出さない。ラインも枠も MB も持たず、ゲージは 10% 刻みで切り捨てた所で止まる。
    /// 公称の速さで動かすので、同じマスの数・同じ段階の出方なら、回収ラインや離した位置が違っても同じ動画になる
    @Test
    func dailyScriptHidesCollectionLine() throws {
        // どちらも、気配は 40〜50%、接近は 50〜60%、警告は 60% を越えてから出る。ニアミスはどちらも ×3
        let first = ReplayScript(replay: try Self.replay(.delivered, released: 0.612, line: 0.625), mode: Self.daily)
        let second = ReplayScript(replay: try Self.replay(.delivered, released: 0.625, line: 0.635), mode: Self.daily)
        #expect(first == second)
        #expect(first.revealedLine == nil)
        #expect(first.budgetBytes == nil)
        #expect(first.donatedBytes == nil)
        #expect(first.squares == 6)
        #expect(first.finalFill == 0.6)
        #expect(first.bluffChanges.isEmpty)

        let timeline = ReplayTimeline(script: first)
        for index in 0..<timeline.frameCount {
            let frame = timeline.frame(at: index)
            #expect(frame.donatedBytes == nil)
            #expect(frame.fill <= 0.6 + 1e-9)
            #expect(frame.squares ?? 0 <= 6)
        }
        // ヒントの段階は 10% の区切り（マスを埋めた時点）にだけ出る
        let curve = DonationCurve.nominal(until: 0.6)
        let boundaries = (0...6).map { curve.time(reaching: Double($0) / 10) }
        for change in first.stageChanges {
            #expect(boundaries.contains { abs($0 - change.time) < 1e-9 })
        }
    }

    /// デイリーで回収されたときは、少なくとも 1 マスを 💥 にして「全メモリ回収」で止める（回収ラインと「○% 越えた」は出さない）
    @Test
    func dailyCollectedStopsAtCollection() throws {
        let script = ReplayScript(replay: try Self.replay(.collected, released: 0.611, line: 0.605), mode: Self.daily)
        #expect(script.result == .collected)
        #expect(script.squares == 6)
        #expect(script.revealedLine == nil)
        let early = ReplayScript(replay: try Self.replay(.collected, released: 0.04, line: 0.035), mode: Self.daily)
        #expect(early.squares == 1)
        #expect(early.finalFill == 0.1)
    }

    /// 会長の台詞は、ラウンドの画面（`ChairmanLines`）と同じものを出す
    @Test(arguments: [ScreenshotDemo.Scene.sign, .approach, .warning])
    func chairmanLinesMatchRoundScreen(scene: ScreenshotDemo.Scene) throws {
        let engine = RoundEngine(probe: SimulatedMemoryProbe(totalBytes: 2_048 * Self.megabyte), thermalState: { .nominal })
        engine.showDemo(scene)
        let script = ReplayScript(replay: try Self.replay(.delivered, released: 0.62, line: 0.64), mode: .express)
        let frame = ReplayFrame(
            scene: .donating,
            fill: 0.5,
            donatedBytes: 0,
            squares: nil,
            stage: engine.hintStage,
            bluff: .none,
            airshipScale: 1,
            noiseFrame: nil,
            stampProgress: 0,
            endCardOpacity: 0
        )
        #expect(ReplayChairman.line(frame: frame, script: script) == ChairmanLines.line(for: engine))
        #expect(ReplayChairman.isLeaning(frame: frame) == ChairmanLines.isLeaning(engine))
    }

    // MARK: - 音

    /// プロペラは接近で鳴らし始めて警告で大きくし、離したところで止める。納品は判子とベル、回収は汽笛、明細書で印字
    @Test
    func soundCuesFollowRoundEvents() throws {
        let delivered = try Self.timeline(.delivered, released: 0.63, line: 0.64)
        let cues = delivered.soundCues
        let propeller = try #require(cues.first { $0.effect == .propeller })
        let approach = try #require(delivered.script.stageChanges.first { $0.stage == .approach })
        let warning = try #require(delivered.script.stageChanges.first { $0.stage == .warning })
        #expect(abs(propeller.start - delivered.videoTime(ofRoundTime: approach.time)) < 1e-9)
        #expect(propeller.level == RoundSounds.approachLevel)
        #expect(abs((propeller.levelChange?.time ?? 0) - delivered.videoTime(ofRoundTime: warning.time)) < 1e-9)
        #expect(propeller.stop == delivered.resultStart)
        #expect(cues.contains(ReplaySoundCue(effect: .delivered, start: delivered.resultStart)))
        #expect(cues.contains { $0.effect == .receipt && $0.start > delivered.endCardStart })

        let collected = try Self.timeline(.collected, released: 0.611, line: 0.605)
        #expect(collected.soundCues.contains(ReplaySoundCue(effect: .whistle, start: collected.resultStart)))
        #expect(!collected.soundCues.contains { $0.effect == .delivered })
    }

    /// 重ねた音は動画の長さ分あり、鳴らしたところに音が入っている
    @Test
    func mixedAudioCoversVideo() throws {
        let cues = [ReplaySoundCue(effect: .delivered, start: 1), ReplaySoundCue(effect: .propeller, start: 2, stop: 9, fadeOut: 0.15)]
        let audio = try ReplayAudioMixer.mix(cues: cues, duration: 10)
        #expect(audio.count == 441_000)
        #expect(audio[0..<44_100].allSatisfy { $0 == 0 })
        #expect(audio[44_100..<88_200].contains { abs($0) > 0.01 })
        // プロペラ（5 秒の音）は、止めるまで繰り返す
        #expect(audio[(8 * 44_100)..<(9 * 44_100)].contains { abs($0) > 0.01 })
        #expect(audio[(9 * 44_100 + 7_000)...].allSatisfy { $0 == 0 })
        #expect(audio.allSatisfy { abs($0) <= 1 })
    }
}

// MARK: - 書き出し

extension ReplayTests {
    /// 短いラウンドの動画を書き出し、長さ・大きさ・コマの速さ・音のトラックを AVAsset で確かめる。書き出しの間の使用量の増え方も見る。
    /// 環境変数 `UNCLERAM_REPLAY_VIDEO_DIR` があれば、ふつうの長さの動画（速達便の納品とデイリーの回収）と、何コマかの画像をそこに書き出す
    /// （xcodebuild では `TEST_RUNNER_UNCLERAM_REPLAY_VIDEO_DIR=<フォルダ>` で渡す）
    @Test
    func exportedVideoHasExpectedFormat() async throws {
        let replay = try Self.replay(.delivered, released: 0.12, line: 0.64)
        let script = ReplayScript(replay: replay, mode: .express)
        let url = try ReplayVideoFiles.makeURL()
        defer { ReplayVideoFiles.remove(url) }
        let content = try Self.content(replay: replay, mode: .express)
        // 書体や絵を読み込む最初の 1 回の分は除いて量る（1 コマ描いておく）
        let timeline = ReplayTimeline(script: script)
        _ = ReplayVideoMaker.render(timeline.frame(at: 30), script: script, speed: timeline.speed, content: content)
        // 描いた絵は、描くたびに手放す。全部のコマを 2 回描いても、2 回目は 1 回目より増えない（コマを持ち続けると、2 回目に 1.2GB 増える）。
        // 1 回目に増える分は描くときの絵の置き場で、環境で大きく違う（Mac +80MB、iOS Simulator +10MB、CI の Mac の仮想マシン +470MB）
        let renderBefore = ProcessMemory.footprintBytes() ?? 0
        var renderPeaks: [UInt64] = []
        for _ in 0..<2 {
            var peak = renderBefore
            for index in 0..<timeline.frameCount {
                _ = ReplayVideoMaker.render(timeline.frame(at: index), script: script, speed: timeline.speed, content: content)
                peak = max(peak, ProcessMemory.footprintBytes() ?? 0)
            }
            renderPeaks.append(peak)
        }
        let renderGrowth = Double(renderPeaks[0] > renderBefore ? renderPeaks[0] - renderBefore : 0) / Double(Self.megabyte)
        let secondPass = Double(renderPeaks[1] > renderPeaks[0] ? renderPeaks[1] - renderPeaks[0] : 0) / Double(Self.megabyte)
        #expect(secondPass < 64)
        let before = ProcessMemory.footprintBytes() ?? 0
        var peak = before
        let video = try await ReplayVideoMaker.make(script: script, content: content, to: url) { _ in
            peak = max(peak, ProcessMemory.footprintBytes() ?? 0)
        }
        let after = ProcessMemory.footprintBytes() ?? 0
        #expect(abs(video.duration - Double(timeline.frameCount) / 30) < 1e-9)

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - video.duration) < 0.1)
        let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await videoTrack.load(.naturalSize) == CGSize(width: 1_080, height: 1_920))
        #expect(abs(try await videoTrack.load(.nominalFrameRate) - 30) < 0.5)
        #expect(try await !asset.loadTracks(withMediaType: .audio).isEmpty)
        // 1 コマずつ書いて手放すので、コマの数（155 コマ × 8MB = 1.2GB）に比例して増えない。符号化を待つコマは 6 コマまで（YUV で 1 コマ 3MB）。
        // 増える分の多くは符号化の係の中の分で、書き終えると戻る（Mac は +30〜140MB）。iOS Simulator はソフトウェアで符号化するので、
        // 係が 40 コマほどを中に持ち、+410MB ほどで頭打ちになる（描くだけなら +10MB。実機は Mac と同じくハードウェアで符号化する）
        let growth = Double(peak > before ? peak - before : 0) / Double(Self.megabyte)
        let remaining = Double(after > before ? after - before : 0) / Double(Self.megabyte)
        print("replay: render +\(Int(renderGrowth)) MB (again +\(Int(secondPass)) MB), export +\(Int(growth)) MB")
        print("replay: +\(Int(remaining)) MB after the export")
        #if targetEnvironment(simulator)
        #expect(growth < 600)
        #else
        #expect(growth < 300)
        #endif

        if let directory = ProcessInfo.processInfo.environment["UNCLERAM_REPLAY_VIDEO_DIR"] {
            try await Self.writeSamples(to: URL(fileURLWithPath: directory, isDirectory: true))
        }
    }

    /// 共有のプレビューを閉じたとき（`discard`）と、作っている途中で止めたときは、動画のファイルを消す
    @Test
    func exportRemovesFileOnDiscard() async throws {
        let replay = try Self.replay(.delivered, released: 0.05, line: 0.64)
        let script = ReplayScript(replay: replay, mode: .express)
        let content = try Self.content(replay: replay, mode: .express)
        let export = ShareVideoExport()
        export.start(script: script, content: content, key: "a")
        let deadline = ContinuousClock.now + .seconds(60)
        while export.video == nil, export.state != .failed, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let video = try #require(export.video)
        #expect(FileManager.default.fileExists(atPath: video.url.path))
        export.discard()
        #expect(!FileManager.default.fileExists(atPath: video.url.deletingLastPathComponent().path))
        #expect(export.state == .idle)

        // 作っている途中で止めても、書きかけのファイルを残さない
        export.start(script: script, content: content, key: "b")
        try await Task.sleep(for: .milliseconds(100))
        export.discard()
        try await Task.sleep(for: .milliseconds(500))
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: ReplayVideoFiles.directory.path)) ?? []
        #expect(leftovers.isEmpty, "\(leftovers)")
    }

    private static func content(replay: RoundReplay, mode: ShareSummary.Mode) throws -> TributeStatementContent {
        let outcome = RoundOutcome(
            kind: replay.result == .collected ? .collected : .delivered,
            plan: plan(line: replay.collectionLine),
            budgetBytes: replay.recording.budgetBytes,
            donatedBytes: replay.donatedBytes,
            stoppedAtSafetyLine: false
        )
        let summary = try #require(ShareSummary(outcome: outcome, mode: mode))
        return TributeStatementContent(summary: summary, device: "iPhone 17 Pro（12GB）", price: .japan, isMac: false)
    }

    /// 目で確かめるための動画と、何コマかの画像
    private static func writeSamples(to folder: URL) async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        struct Sample {
            let name: String
            let replay: RoundReplay
            let mode: ShareSummary.Mode
        }
        let samples = [
            Sample(name: "express-delivered", replay: try replay(.delivered, released: 0.63, line: 0.64), mode: .express),
            Sample(name: "express-collected", replay: try replay(.collected, released: 0.611, line: 0.605), mode: .express),
            Sample(name: "daily-collected", replay: try replay(.collected, released: 0.611, line: 0.605), mode: daily)
        ]
        for sample in samples {
            let script = ReplayScript(replay: sample.replay, mode: sample.mode)
            let url = folder.appendingPathComponent("replay-\(sample.name).mp4")
            try? FileManager.default.removeItem(at: url)
            let started = ContinuousClock.now
            let content = try content(replay: sample.replay, mode: sample.mode)
            let video = try await ReplayVideoMaker.make(script: script, content: content, to: url)
            print("replay \(sample.name): \(video.duration) s, made in \(started.duration(to: .now))")
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let timeline = ReplayTimeline(script: script)
            let warning = script.stageChanges.first { $0.stage == .warning }.map { timeline.videoTime(ofRoundTime: $0.time) + 0.05 }
            let times = [
                0.3,
                timeline.resultStart - 1.5,
                warning ?? timeline.resultStart - 0.2,
                timeline.resultStart + 1,
                timeline.totalDuration - 0.5
            ]
            for (index, time) in times.enumerated() {
                let image = try await generator.image(at: CMTime(seconds: max(0, time), preferredTimescale: 600)).image
                if let png = ShareImageRenderer.pngData(of: image) {
                    try png.write(to: folder.appendingPathComponent("replay-\(sample.name)-\(index).png"))
                }
            }
        }
    }
}

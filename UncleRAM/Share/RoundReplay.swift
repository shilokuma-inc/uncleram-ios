import Foundation

/// 献上中の記録（リプレイ動画の元。docs/SPEC.md「共有機能」の動画）。
///
/// 献上量（枠に対する割合）は 0.1 秒ごと、ヒントの段階とはったりは変わったときだけ残す。
/// 長く押し続けても大きくならないよう、献上量の点が `maximumSamples` を越えたら 1 つおきに間引き、間隔を倍にする
/// （どのラウンドでも 2KB ほど。ふつうのラウンドは 11 秒ほどで終わるので、間引かずに収まる）。
/// 記録はメモリに置くだけで、確保・解放には関わらない
nonisolated struct RoundRecording: Sendable, Equatable {
    /// 献上量の 1 点。時刻は押し始めてからの秒数
    struct Sample: Sendable, Equatable {
        let time: Float
        let fill: Float
    }

    struct StageChange: Sendable, Equatable {
        let time: Float
        let stage: RoundPlan.HintStage
    }

    /// はったり（偽の気配）の見せ方（`RoundEngine.Bluff` と同じ）
    enum Bluff: Sendable, Equatable {
        case none
        case showing
        case grinning
    }

    struct BluffChange: Sendable, Equatable {
        let time: Float
        let bluff: Bluff
    }

    /// 献上量を残す間隔（秒）
    static let sampleInterval = 0.1
    /// 献上量の点の上限。越えたら 1 つおきに間引く
    static let maximumSamples = 256

    let budgetBytes: UInt64
    /// 実際に効く安全ライン（枠に対する割合）
    let safetyLineFill: Double
    let isPractice: Bool
    private(set) var samples: [Sample] = []
    private(set) var stageChanges: [StageChange] = []
    private(set) var bluffChanges: [BluffChange] = []
    /// 今の、献上量を残す間隔。間引くたびに倍になる
    private(set) var interval = Self.sampleInterval

    init(budgetBytes: UInt64, safetyLineFill: Double, isPractice: Bool) {
        self.budgetBytes = budgetBytes
        self.safetyLineFill = safetyLineFill
        self.isPractice = isPractice
    }

    /// 献上量を残す。前の点から `interval` 経っていなければ残さない
    mutating func record(fill: Double, at time: Double) {
        if let last = samples.last, time - Double(last.time) < interval - 1e-6 {
            return
        }
        samples.append(Sample(time: Float(time), fill: Float(fill)))
        if samples.count > Self.maximumSamples {
            thin()
        }
    }

    /// 離した瞬間の献上量。間隔に関係なく、最後の点として必ず残す（前の点より少なければ、前の点も直す）
    mutating func finish(fill: Double, at time: Double) {
        samples.removeAll { Double($0.time) >= time }
        samples = samples.map { Sample(time: $0.time, fill: min($0.fill, Float(fill))) }
        samples.append(Sample(time: Float(time), fill: Float(fill)))
        if samples.count > Self.maximumSamples {
            thin()
        }
    }

    mutating func record(stage: RoundPlan.HintStage, at time: Double) {
        guard stage != (stageChanges.last?.stage ?? .none) else {
            return
        }
        stageChanges.append(StageChange(time: Float(time), stage: stage))
    }

    mutating func record(bluff: Bluff, at time: Double) {
        guard bluff != (bluffChanges.last?.bluff ?? .none) else {
            return
        }
        bluffChanges.append(BluffChange(time: Float(time), bluff: bluff))
    }

    /// 1 つおきに間引く。最初と最後の点は残す（数が上限 + 1 のときに呼ぶので、最後の点は偶数番目になる）
    private mutating func thin() {
        let last = samples.last
        samples = samples.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
        if let last, samples.last != last {
            samples.append(last)
        }
        interval *= 2
    }

    /// 記録の大きさ（バイト。点と出来事の分だけ）
    var byteCount: Int {
        samples.count * MemoryLayout<Sample>.stride
            + stageChanges.count * MemoryLayout<StageChange>.stride
            + bluffChanges.count * MemoryLayout<BluffChange>.stride
    }
}

/// 1 ラウンドのリプレイ（記録と結果）。無効になったラウンドは作らない（シェアしない）
nonisolated struct RoundReplay: Sendable, Equatable {
    let recording: RoundRecording
    /// 押し始めてから離すまでの秒数
    let duration: Double
    let result: ShareSummary.Result
    /// 離した位置（枠に対する割合）
    let releasedFill: Double
    let donatedBytes: UInt64
    /// 回収ライン。速達便の動画の最後でだけ明かす（デイリーの動画には渡さない。`ReplayScript`）
    let collectionLine: Double
    let nearMissMultiplier: Double
    let isEarlyCollection: Bool

    init?(recording: RoundRecording, duration: Double, outcome: RoundOutcome) {
        switch outcome.kind {
        case .delivered:
            result = .delivered
        case .collected:
            result = .collected
        case .audited:
            result = .audited
        case .voided:
            return nil
        }
        var recording = recording
        recording.finish(fill: outcome.releasedFill, at: duration)
        self.recording = recording
        self.duration = duration
        releasedFill = outcome.releasedFill
        donatedBytes = outcome.donatedBytes
        collectionLine = outcome.plan.collectionLine
        nearMissMultiplier = outcome.nearMissMultiplier
        isEarlyCollection = outcome.plan.isEarlyCollection
    }

    /// 献上量が初めて `fill` に届いた時刻（点の間は線でつなぐ）。届かなかったら nil
    func time(reaching fill: Double) -> Double? {
        let samples = recording.samples
        guard let index = samples.firstIndex(where: { Double($0.fill) >= fill - 1e-9 }) else {
            return nil
        }
        guard index > 0 else {
            return Double(samples[0].time)
        }
        let before = samples[index - 1]
        let after = samples[index]
        let span = Double(after.fill - before.fill)
        let ratio = span > 0 ? (fill - Double(before.fill)) / span : 1
        return Double(before.time) + Double(after.time - before.time) * min(max(ratio, 0), 1)
    }

    /// その時刻に出ていたヒントの段階
    func stage(at time: Double) -> RoundPlan.HintStage {
        recording.stageChanges.last { Double($0.time) <= time + 1e-9 }?.stage ?? .none
    }

    /// 撮影モード（ScreenshotDemo）のリプレイ。記録の代わりに、公称の速さ（`DonationSpeed`）で結果の量まで押したことにする
    static func demo(outcome: RoundOutcome, safetyLineFill: Double) -> RoundReplay? {
        var recording = RoundRecording(
            budgetBytes: outcome.budgetBytes,
            safetyLineFill: safetyLineFill,
            isPractice: outcome.plan.isPractice
        )
        let curve = DonationCurve.nominal(until: outcome.releasedFill)
        for point in curve.points {
            recording.record(fill: point.fill, at: point.time)
            recording.record(stage: outcome.plan.hintStage(at: point.fill), at: point.time)
        }
        return RoundReplay(recording: recording, duration: curve.duration, outcome: outcome)
    }
}

/// 公称の献上の速さ（`DonationSpeed`）で押し続けたときの、時刻と献上量
nonisolated struct DonationCurve: Sendable, Equatable {
    struct Point: Sendable, Equatable {
        let time: Double
        let fill: Double
    }

    /// 0.1 秒ごとの点。最後の点は、ちょうど `target` に届いた時刻
    let points: [Point]

    var duration: Double {
        points.last?.time ?? 0
    }

    /// 0 から `target` まで押したときの点
    static func nominal(until target: Double, interval: Double = RoundRecording.sampleInterval) -> DonationCurve {
        let step = 0.001
        var fill = 0.0
        var elapsed = 0.0
        var slowZoneStart: Double?
        var points = [Point(time: 0, fill: 0)]
        while fill < target {
            if fill >= DonationSpeed.fastZoneEnd, slowZoneStart == nil {
                slowZoneStart = elapsed
            }
            let rate = DonationSpeed.rate(fill: fill, secondsInSlowZone: slowZoneStart.map { elapsed - $0 })
            let next = fill + rate * step
            if next >= target {
                // 届いた時刻を、この 1 歩の中で割り出す
                elapsed += step * (target - fill) / (next - fill)
                fill = target
            } else {
                fill = next
                elapsed += step
            }
            if fill >= target || elapsed - points[points.count - 1].time >= interval - 1e-9 {
                points.append(Point(time: elapsed, fill: fill))
            }
        }
        return DonationCurve(points: points)
    }

    /// 献上量が `fill` に届いた時刻
    func time(reaching fill: Double) -> Double {
        guard let index = points.firstIndex(where: { $0.fill >= fill - 1e-9 }) else {
            return duration
        }
        guard index > 0 else {
            return 0
        }
        let before = points[index - 1]
        let after = points[index]
        let span = after.fill - before.fill
        let ratio = span > 0 ? (fill - before.fill) / span : 1
        return before.time + (after.time - before.time) * min(max(ratio, 0), 1)
    }
}

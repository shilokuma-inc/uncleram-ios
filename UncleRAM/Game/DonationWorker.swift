import Foundation
import Synchronization

/// 長押ししている間、0.1 秒ごとに献上の速さの分だけメモリを確保する。メインスレッドとは別のスレッドで動く。
///
/// 回収ラインを越えそうになったら確保せずに止め、安全ラインに当たったら止める。どちらもイベントでメインに知らせる。
nonisolated final class DonationWorker: Sendable {
    enum Event: Sendable, Equatable {
        /// 回収ラインを越えた
        case collected
        /// 安全ラインに当たって止めた（納品扱い）
        case stoppedAtSafetyLine
        /// ヒントの段階が上がった
        case hintStageChanged(RoundPlan.HintStage)
        /// はったり（偽の気配）を出す位置に来た
        case bluff
    }

    static let tickInterval: TimeInterval = 0.1

    private let plan: RoundPlan
    private let budgetBytes: UInt64
    private let safety: SafetyLine
    private let allocator: Allocator
    private let probe: any MemoryProbe
    private let onEvent: @Sendable (Event) -> Void
    private let stopRequested = Atomic<Bool>(false)
    private let completion = Mutex<Completion>(Completion())

    private struct Completion {
        var finished = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    init(
        plan: RoundPlan,
        budgetBytes: UInt64,
        safety: SafetyLine,
        allocator: Allocator,
        probe: any MemoryProbe,
        onEvent: @escaping @Sendable (Event) -> Void
    ) {
        self.plan = plan
        self.budgetBytes = budgetBytes
        self.safety = safety
        self.allocator = allocator
        self.probe = probe
        self.onEvent = onEvent
    }

    func start() {
        let thread = Thread { [self] in
            run()
        }
        thread.name = "UncleRAM.DonationWorker"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// 確保を止め、ループが終わるまで待つ（確保の途中のチャンクは書き終えてから止まる）
    func stop() async {
        stopRequested.store(true, ordering: .releasing)
        await withCheckedContinuation { continuation in
            let resumeNow = completion.withLock { state -> Bool in
                if state.finished {
                    return true
                }
                state.waiters.append(continuation)
                return false
            }
            if resumeNow {
                continuation.resume()
            }
        }
    }

    private func run() {
        let chunkSize = Double(Allocator.chunkSize)
        let budget = Double(budgetBytes)
        let lineBytes = plan.collectionLine * budget
        let start = ContinuousClock.now
        var lastTick = start
        var slowZoneStart: Double?
        var pendingBytes = 0.0
        var stage = RoundPlan.HintStage.none
        var bluffSent = false

        while !stopRequested.load(ordering: .acquiring) {
            let wait = max(0, Self.tickInterval - lastTick.duration(to: .now).seconds)
            Thread.sleep(forTimeInterval: wait)
            if stopRequested.load(ordering: .acquiring) {
                break
            }
            let now = ContinuousClock.now
            // 確保が速さに追いつかないとき（Mac の大きな枠など）は、遅れを貯めずに速さを頭打ちにする
            let delta = min(lastTick.duration(to: now).seconds, Self.tickInterval)
            lastTick = now
            let elapsed = start.duration(to: now).seconds

            let fill = Double(allocator.allocatedBytes) / budget
            if fill >= DonationSpeed.fastZoneEnd, slowZoneStart == nil {
                slowZoneStart = elapsed
            }
            let rate = DonationSpeed.rate(fill: fill, secondsInSlowZone: slowZoneStart.map { elapsed - $0 })
            pendingBytes += rate * delta * budget
            let count = Int(pendingBytes / chunkSize)
            pendingBytes -= Double(count) * chunkSize

            let batch = allocator.allocate(count: count, safety: safety, probe: probe)
            // 同じ確保で警告と回収ラインを両方越えたときも、回収の前にヒントを出しておく
            reportHints(fill: Double(allocator.allocatedBytes) / budget, stage: &stage, bluffSent: &bluffSent)
            // 回収ラインは必ず安全ラインより手前にあるので、越えるまで確保してから回収にする（献上量はラインの先になる）
            if Double(allocator.allocatedBytes) > lineBytes {
                onEvent(.collected)
                break
            }
            if batch.blockedBySafetyLine {
                onEvent(.stoppedAtSafetyLine)
                break
            }
        }
        markFinished()
    }

    /// ヒントの段階が上がったら知らせる（1 回の確保で 2 段階を越えても、1 → 2 → 3 の順にすべて知らせる）。
    /// はったりの位置に来たら、本物の気配がまだ出ていなければ知らせる
    private func reportHints(fill: Double, stage: inout RoundPlan.HintStage, bluffSent: inout Bool) {
        let newStage = plan.hintStage(at: fill)
        while stage < newStage, let next = RoundPlan.HintStage(rawValue: stage.rawValue + 1) {
            stage = next
            onEvent(.hintStageChanged(next))
        }
        if !bluffSent, let bluffAt = plan.bluffAt, fill >= bluffAt {
            bluffSent = true
            if stage == .none {
                onEvent(.bluff)
            }
        }
    }

    private func markFinished() {
        let waiters = completion.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.finished = true
            let list = state.waiters
            state.waiters.removeAll()
            return list
        }
        waiters.forEach { $0.resume() }
    }
}

nonisolated extension Duration {
    /// 秒（小数）
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

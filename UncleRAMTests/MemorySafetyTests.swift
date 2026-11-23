import Foundation
import Synchronization
import Testing
@testable import UncleRAM

/// 安全ライン・確保と解放・ラウンドの状態遷移を、Simulator と同じ仮の枠で確かめる
@MainActor
struct MemorySafetyTests {
    private static let megabyte: UInt64 = 1_048_576

    @Test
    func safetyLineChecksBothConditions() {
        let safety = SafetyLine(budgetBytes: 2_048 * Self.megabyte)
        let chunk = Allocator.chunkSize
        // 1 つ目: 献上量 + 確保量 ≤ 枠 × 85%
        #expect(safety.allows(donated: 0, adding: chunk, available: 4_096 * Self.megabyte))
        #expect(!safety.allows(donated: safety.donationLimitBytes, adding: chunk, available: 4_096 * Self.megabyte))
        // 2 つ目: 残量 − 確保量 ≥ max(枠 × 15%, 200MB)
        #expect(safety.reserveBytes == UInt64(Double(2_048 * Self.megabyte) * 0.15))
        #expect(!safety.allows(donated: 0, adding: chunk, available: safety.reserveBytes + chunk - 1))
        #expect(safety.allows(donated: 0, adding: chunk, available: safety.reserveBytes + chunk))
        // 枠が小さいと、200MB の下限が効く
        #expect(SafetyLine(budgetBytes: 700 * Self.megabyte).reserveBytes == 200 * Self.megabyte)
    }

    @Test
    func smallBudgetIsNotPlayable() {
        #expect(!SafetyLine(budgetBytes: 599 * Self.megabyte).isPlayable)
        #expect(SafetyLine(budgetBytes: 600 * Self.megabyte).isPlayable)
    }

    /// 残量が少ないと、安全ラインは 85% より手前になる
    @Test
    func effectiveSafetyLineFollowsAvailableMemory() {
        let safety = SafetyLine(budgetBytes: 1_000 * Self.megabyte)
        #expect(safety.effectiveLine(available: 10_000 * Self.megabyte) == 0.85)
        #expect(abs(safety.effectiveLine(available: 800 * Self.megabyte) - 0.6) < 1e-9)
    }

    /// 安全ラインに当たると確保をやめ、全解放で 0 に戻る
    @Test
    func allocatorStopsAtSafetyLineAndReleasesAll() {
        let allocator = Allocator(fillMode: .sparse)
        // 枠 300MB の仮の端末: 残り 200MB を残すので、確保できるのは 100MB（16MB × 6）まで
        let probe = SimulatedMemoryProbe(totalBytes: 300 * Self.megabyte)
        let safety = SafetyLine(budgetBytes: probe.budgetBytes())
        let batch = allocator.allocate(count: 20, safety: safety, probe: probe)
        #expect(batch.blockedBySafetyLine)
        #expect(batch.allocated == 6)
        #expect(allocator.allocatedBytes == 6 * Allocator.chunkSize)
        let duration = allocator.releaseAll()
        #expect(allocator.allocatedBytes == 0)
        #expect(duration < 0.2)
    }

    /// 本番の書き込み方は、ページごとに少しだけ乱数を書く方式（docs/SPEC.md「書き込み方の見直し」）
    @Test
    func productionFillModeIsSparse() {
        #expect(Allocator().fillMode == .sparse)
        #expect(RoundEngine(thermalState: { .nominal }).allocator.fillMode == .sparse)
    }

    /// 書き込みの数えは、書き込みの間だけ奇数になり、1 回の確保で 2 つ進む（計測で、使用量と献上量を同じ状態で量るため）
    @Test
    func fillSequenceIsEvenOutsideWrites() {
        let allocator = Allocator(fillMode: .sparse)
        let probe = SimulatedMemoryProbe(totalBytes: 2_048 * Self.megabyte)
        let safety = SafetyLine(budgetBytes: probe.budgetBytes())
        #expect(allocator.fillSequenceNumber == 0)
        _ = allocator.allocate(count: 2, safety: safety, probe: probe)
        #expect(allocator.fillSequenceNumber == 2)
        _ = allocator.allocate(count: 1, safety: safety, probe: probe)
        #expect(allocator.fillSequenceNumber.isMultiple(of: 2))
        #expect(allocator.fillSequenceNumber == 4)
        allocator.releaseAll()
    }

    /// 離すと納品になり、結果を出す前に全メモリが解放されている
    @Test
    func releasingDeliversAndFreesMemory() async throws {
        let engine = RoundEngine(
            allocator: Allocator(fillMode: .sparse),
            probe: SimulatedMemoryProbe(totalBytes: 640 * Self.megabyte),
            random: SplitMix64(seed: 1),
            thermalState: { .nominal }
        )
        #expect(engine.phase == .ready)
        engine.beginHold()
        #expect(engine.phase == .donating)
        // 混んだランナーでも揺らがないよう、時間を決め打ちせずに献上量が増えるまで待つ（最大 3 秒）
        let deadline = ContinuousClock.now + .seconds(3)
        while engine.donatedBytes == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        engine.endHold(.released)
        let outcome = try #require(await engine.waitForResult())
        #expect(outcome.kind == .delivered)
        #expect(outcome.donatedBytes > 0)
        #expect(engine.allocator.allocatedBytes == 0)
        #expect(engine.lastReleaseDuration != nil)
        engine.reset()
        #expect(engine.phase == .ready)
    }

    /// 離した瞬間に書き込み中だったチャンクは献上量に数えない。解放の時間には、確保を止めるのを待つ時間も入る
    @Test
    func releaseSettlesAtAmountWhenReleased() async throws {
        let probe = GatedMemoryProbe(totalBytes: 2_048 * Self.megabyte)
        let engine = RoundEngine(
            allocator: Allocator(fillMode: .sparse),
            probe: probe,
            random: SplitMix64(seed: 6),
            thermalState: { .nominal }
        )
        engine.beginHold()
        let deadline = ContinuousClock.now + .seconds(5)
        while engine.donatedBytes == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        // 次の確保の途中（安全ラインを確かめるところ）でワーカーを止めておき、その間に離す
        probe.close()
        while !probe.isWaiting, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(probe.isWaiting)
        let atRelease = engine.donatedBytes
        engine.endHold(.released)
        try await Task.sleep(for: .milliseconds(300))
        probe.open()

        let outcome = try #require(await engine.waitForResult())
        #expect(outcome.kind == .delivered)
        #expect(outcome.donatedBytes == atRelease)
        #expect(engine.allocator.allocatedBytes == 0)
        let release = try #require(engine.lastReleaseDuration)
        let unmap = try #require(engine.lastUnmapDuration)
        #expect(release >= 0.3)
        #expect(unmap <= release)
    }

    /// 中止されたタスクから結果を待っても、解放が進んで結果が出る（計測の「中止」・バックグラウンド・画面を閉じたとき）。
    /// 中止済みのタスクの Task.sleep は待たずにすぐ投げるので、待ち方によってはメインアクターを手放さず、解放の処理が進まない
    @Test(.timeLimit(.minutes(1)))
    func waitingFromCancelledTaskStillSettles() async throws {
        let engine = try await donatingEngine(seed: 8)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            engine.endHold(.released)
            return await engine.waitForResult()
        }
        let outcome = await task.value
        #expect(outcome?.kind == .delivered)
        #expect(engine.allocator.allocatedBytes == 0)
    }

    /// バックグラウンドへの移行は無効（スコア 0）
    @Test
    func backgroundVoidsRound() async throws {
        let engine = RoundEngine(
            allocator: Allocator(fillMode: .sparse),
            probe: SimulatedMemoryProbe(totalBytes: 640 * Self.megabyte),
            random: SplitMix64(seed: 2),
            thermalState: { .nominal }
        )
        engine.beginHold()
        try await Task.sleep(for: .milliseconds(250))
        engine.void(.background)
        let outcome = try #require(await engine.waitForResult())
        #expect(outcome.kind == .voided(.background))
        #expect(outcome.score == 0)
        #expect(engine.allocator.allocatedBytes == 0)
    }

    private func donatingEngine(seed: UInt64) async throws -> RoundEngine {
        let engine = RoundEngine(
            allocator: Allocator(fillMode: .sparse),
            probe: SimulatedMemoryProbe(totalBytes: 640 * Self.megabyte),
            random: SplitMix64(seed: seed),
            thermalState: { .nominal }
        )
        engine.beginHold()
        let deadline = ContinuousClock.now + .seconds(3)
        while engine.donatedBytes == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        return engine
    }

    /// inactive で離したあと、続けてバックグラウンドに移ったら無効になる（ホームに戻るだけで確定できる抜け道をなくす）
    @Test
    func inactiveThenBackgroundVoidsRound() async throws {
        let duringSettling = try await donatingEngine(seed: 3)
        duringSettling.endHold(.inactive)
        duringSettling.void(.background)
        #expect(try #require(await duringSettling.waitForResult()).kind == .voided(.background))

        let afterResult = try await donatingEngine(seed: 4)
        afterResult.endHold(.inactive)
        #expect(try #require(await afterResult.waitForResult()).kind == .delivered)
        afterResult.void(.background)
        #expect(try #require(await afterResult.waitForResult()).kind == .voided(.background))
        #expect(afterResult.allocator.allocatedBytes == 0)
    }

    /// inactive のあと前面に戻ったら（コントロールセンターなど）、納品のまま確定する
    @Test
    func inactiveThenActiveKeepsDelivery() async throws {
        let engine = try await donatingEngine(seed: 5)
        engine.endHold(.inactive)
        #expect(try #require(await engine.waitForResult()).kind == .delivered)
        engine.sceneBecameActive()
        engine.void(.background)
        #expect(try #require(await engine.waitForResult()).kind == .delivered)
    }

    /// 枠が小さく、残す量（200MB）が先に効く端末では、画面の安全ラインも 85% より手前になる
    @Test
    func effectiveSafetyLineIsShownForSmallBudget() {
        let engine = RoundEngine(
            probe: SimulatedMemoryProbe(totalBytes: 640 * Self.megabyte),
            thermalState: { .nominal }
        )
        #expect(abs(engine.safetyLineFill - 440.0 / 640.0) < 1e-9)
    }

    /// 発熱が serious 以上なら始められない
    @Test
    func seriousThermalStateBlocksRound() {
        let engine = RoundEngine(
            probe: SimulatedMemoryProbe(totalBytes: 2_048 * Self.megabyte),
            thermalState: { .serious }
        )
        #expect(engine.phase == .unavailable(.thermal))
        engine.beginHold()
        #expect(engine.phase == .unavailable(.thermal))
    }
}

/// 確保の途中でワーカーを止めておける仮の端末。離した瞬間に、ワーカーがまだチャンクを確保している場面を作る
nonisolated final class GatedMemoryProbe: MemoryProbe {
    private let base: SimulatedMemoryProbe
    private let closed = Atomic<Bool>(false)
    private let waiting = Atomic<Bool>(false)
    private let gate = DispatchSemaphore(value: 0)

    init(totalBytes: UInt64) {
        base = SimulatedMemoryProbe(totalBytes: totalBytes)
    }

    /// ワーカーが止まって待っているか
    var isWaiting: Bool {
        waiting.load(ordering: .acquiring)
    }

    /// 次に残量を聞かれたところで、ワーカーを止める
    func close() {
        closed.store(true, ordering: .releasing)
    }

    /// 止めていたワーカーを進める
    func open() {
        closed.store(false, ordering: .releasing)
        gate.signal()
    }

    func budgetBytes() -> UInt64 {
        base.budgetBytes()
    }

    func availableBytes(allocatedByRound: UInt64) -> UInt64 {
        if closed.load(ordering: .acquiring) {
            waiting.store(true, ordering: .releasing)
            gate.wait()
        }
        return base.availableBytes(allocatedByRound: allocatedByRound)
    }
}

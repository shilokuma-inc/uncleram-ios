import Foundation
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
        try await Task.sleep(for: .milliseconds(450))
        engine.endHold(.released)
        let outcome = try #require(await engine.waitForResult())
        #expect(outcome.kind == .delivered)
        #expect(outcome.donatedBytes > 0)
        #expect(engine.allocator.allocatedBytes == 0)
        #expect(engine.lastReleaseDuration != nil)
        engine.reset()
        #expect(engine.phase == .ready)
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

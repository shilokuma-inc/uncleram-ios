import Foundation
import Testing
@testable import UncleRAM

/// 計測（BenchRunner）を、通常のラウンドと同時に動かさないこと
@MainActor
struct BenchRunnerTests {
    private static let megabyte: UInt64 = 1_048_576

    /// 献上中は計測を始めない（書き込み方を途中で変えたり、計測側が中断したりしないように）
    @Test
    func benchDoesNotStartWhileDonating() async throws {
        let engine = RoundEngine(
            allocator: Allocator(fillMode: .sparse),
            probe: SimulatedMemoryProbe(totalBytes: 640 * Self.megabyte),
            random: SplitMix64(seed: 7),
            thermalState: { .nominal }
        )
        let bench = BenchRunner(engine: engine)
        #expect(bench.canStart)

        engine.beginHold()
        #expect(engine.phase == .donating)
        #expect(!bench.canStart)
        bench.start(rounds: 1, fillMode: .full)
        #expect(!bench.isRunning)
        #expect(!engine.isAutomated)
        #expect(engine.allocator.fillMode == .sparse)

        engine.endHold(.released)
        _ = try #require(await engine.waitForResult())
        #expect(bench.canStart)
    }
}

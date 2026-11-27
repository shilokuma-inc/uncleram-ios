import Foundation
import Testing
@testable import UncleRAM

/// 計測（BenchRunner）を、通常のラウンドと同時に動かさないこと。「計測」ボタンの出し方（#51）
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

    /// 「計測」ボタンは、切り替えられる環境で設定がオンのときだけ出す。起動引数で計測したときは、設定に関係なく出す
    @Test(arguments: [
        (false, false, false, false),
        (false, true, false, false),
        (true, false, false, false),
        (true, true, false, true),
        (false, false, true, true),
        (true, false, true, true)
    ])
    func benchButtonVisibility(isSwitchable: Bool, isEnabled: Bool, isLaunchedForBench: Bool, expected: Bool) {
        let shows = BenchAccess.showsButton(isSwitchable: isSwitchable, isEnabled: isEnabled, isLaunchedForBench: isLaunchedForBench)
        #expect(shows == expected)
    }

    #if DEBUG
    /// Debug ビルドでも、設定がオフ（既定）なら「計測」ボタンを出さない（TestFlight と同じ見え方にする）。
    /// Release では切り替えられるかを `AppTransaction` から非同期に決めるので、Debug だけで確かめる
    @Test
    func benchButtonIsHiddenByDefaultInDebug() {
        let bench = BenchRunner(engine: RoundEngine())
        #expect(bench.isAvailable)
        #expect(!bench.isLaunchedForBench)
        #expect(!bench.showsButton(isEnabled: false))
        #expect(bench.showsButton(isEnabled: true))
    }
    #endif

    /// 間を空けずに 5 回タップすると切り替わり、数え直す
    @Test
    func fiveQuickTapsToggle() {
        var counter = RepeatedTapCounter(requiredTaps: 5, maxInterval: 2)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let results = (0..<5).map { counter.register(at: start.addingTimeInterval(Double($0) * 0.3)) }
        #expect(results == [false, false, false, false, true])
        #expect(counter.taps == 0)
        // 続けてもう 1 回タップしても、1 回目から数える
        let again = counter.register(at: start.addingTimeInterval(1.6))
        #expect(!again)
        #expect(counter.taps == 1)
    }

    /// タップの間が空きすぎたら、1 回目から数え直す
    @Test
    func slowTapRestartsCount() {
        var counter = RepeatedTapCounter(requiredTaps: 5, maxInterval: 2)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        for index in 0..<4 {
            let toggled = counter.register(at: start.addingTimeInterval(Double(index)))
            #expect(!toggled)
        }
        #expect(counter.taps == 4)
        // 4 回目から 2 秒を越えて空いた
        let late = start.addingTimeInterval(3 + 2.1)
        let lateToggled = counter.register(at: late)
        #expect(!lateToggled)
        #expect(counter.taps == 1)
        let rest = (1..<5).map { counter.register(at: late.addingTimeInterval(Double($0) * 1.5)) }
        #expect(rest == [false, false, false, true])
    }

    /// 設定の「計測」ボタンの表示は、既定でオフ。次に起動したときも覚えていて、データの初期化で消える
    @Test
    func showsBenchButtonPersistsAndResets() throws {
        let suiteName = "UncleRAMTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LocalStore(defaults: defaults)
        #expect(!store.showsBenchButton)
        store.showsBenchButton = true
        #expect(LocalStore(defaults: defaults).showsBenchButton)

        store.resetAll()
        #expect(!store.showsBenchButton)
        #expect(!LocalStore(defaults: defaults).showsBenchButton)
    }
}

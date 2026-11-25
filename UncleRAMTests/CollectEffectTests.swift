import Foundation
import Testing
@testable import UncleRAM

/// 回収演出の時間割が、docs/SPEC.md「アクセシビリティ」（動きを減らす・点滅）のとおりかを確かめる
struct CollectEffectTests {
    nonisolated static let styles: [CollectEffectTimeline.Style] = [
        .full,
        CollectEffectTimeline.Style(isSubdued: true, freezesColorShift: false),
        CollectEffectTimeline.Style(isSubdued: false, freezesColorShift: true),
        CollectEffectTimeline.Style(isSubdued: true, freezesColorShift: true)
    ]

    /// 1ms ごとに見た時刻と状態
    private static func frames(_ timeline: CollectEffectTimeline) -> [(time: TimeInterval, frame: CollectEffectTimeline.Frame)] {
        stride(from: 0, through: timeline.duration + 1, by: 0.001).map { ($0, timeline.frame(at: $0)) }
    }

    /// グリッチの形が切り替わるのは、どの 1 秒の間でも 3 回まで（1 秒に 3 回を超えて点滅させない）
    @Test(arguments: styles)
    func glitchNeverChangesMoreThanThreeTimesPerSecond(style: CollectEffectTimeline.Style) {
        let frames = Self.frames(CollectEffectTimeline(style: style))
        var changes: [TimeInterval] = []
        for (previous, current) in zip(frames, frames.dropFirst()) where previous.frame.glitch != current.frame.glitch {
            changes.append(current.time)
        }
        for start in changes {
            let inWindow = changes.filter { $0 >= start && $0 < start + 1 }
            #expect(inWindow.count <= CollectEffectTimeline.maximumFlashesPerSecond)
        }
    }

    /// 控えめにするときは、グリッチと揺れを止め、飛行船の影と判子だけにする（動きは、ふわっと出すだけ）
    @Test
    func subduedStyleHasNoGlitchOrShake() {
        let timeline = CollectEffectTimeline(style: CollectEffectTimeline.Style(isSubdued: true, freezesColorShift: false))
        for (_, frame) in Self.frames(timeline) {
            #expect(frame.glitch == nil)
            #expect(frame.shake == 0)
            #expect(frame.airshipOffset == .zero)
            #expect(frame.stampScale == 1)
            #expect(frame.colorShift == 1)
        }
        #expect(timeline.finalFrame.airshipOpacity == 1)
        #expect(timeline.finalFrame.stampOpacity == 1)
    }

    /// 「点滅する光を弱める」がオンなら、赤と青のずれを動かさない。グリッチも段階を踏まず、1 回で出す
    @Test
    func dimmedFlashingFreezesColorShift() {
        let timeline = CollectEffectTimeline(style: CollectEffectTimeline.Style(isSubdued: false, freezesColorShift: true))
        for (_, frame) in Self.frames(timeline) {
            #expect(frame.colorShift == 1)
        }
        #expect(timeline.glitchChanges.count == 1)
    }

    /// ふつうの見せ方では、グリッチが 3 段階で動き、赤と青のずれも大きいところから収まる
    @Test
    func fullStyleGlitchesAndSettles() {
        let timeline = CollectEffectTimeline(style: .full)
        let glitches = Set(Self.frames(timeline).compactMap(\.frame.glitch))
        #expect(glitches == Set(CollectEffectTimeline.Glitch.allCases))
        #expect(timeline.frame(at: 0.3).shake != 0)
        #expect(timeline.frame(at: 0.95).colorShift > 1)
        #expect(timeline.finalFrame.glitch == .settled)
        #expect(timeline.finalFrame.colorShift == 1)
    }

    /// 最後はすべて出て止まり、「結果を見る」を押せる。出る前は押せない
    @Test(arguments: styles)
    func everythingIsVisibleAtTheEnd(style: CollectEffectTimeline.Style) {
        let timeline = CollectEffectTimeline(style: style)
        let last = timeline.finalFrame
        #expect(last == timeline.frame(at: timeline.duration))
        #expect(last.airshipOpacity == 1)
        #expect(last.headlineOpacity == 1)
        #expect(last.stampOpacity == 1)
        #expect(last.stampScale == 1)
        #expect(last.detailsOpacity == 1)
        #expect(last.actionsOpacity == 1)
        #expect(last.shake == 0)
        #expect(last.airshipOffset == .zero)
        #expect(last.isActionEnabled)
        #expect(!timeline.frame(at: 0).isActionEnabled)
    }

    /// 「控えめにする」は、今は「視差効果を減らす」だけで決まる。「点滅する光を弱める」は赤と青のずれだけを止める
    @Test
    func currentStyleFollowsAccessibilitySettings() {
        #expect(CollectEffectTimeline.Style.current(reduceMotion: false, dimsFlashingLights: false) == .full)
        #expect(CollectEffectTimeline.Style.current(reduceMotion: true, dimsFlashingLights: false).isSubdued)
        let dimmed = CollectEffectTimeline.Style.current(reduceMotion: false, dimsFlashingLights: true)
        #expect(!dimmed.isSubdued)
        #expect(dimmed.freezesColorShift)
    }

    /// 献上分・回収ライン・超過分は切り捨てた MB で出し、超過分は画面の 2 つの値の差にする
    @Test
    func figuresAreConsistentMegabytes() {
        let megabyte: UInt64 = 1_048_576
        let plan = RoundPlan(isEarlyCollection: false, collectionLine: 0.58, hintThresholds: [0.43, 0.50, 0.56], bluffAt: nil)
        // 枠 2,048 MB の 58% は 1,187.84 MB、献上 1,248 MB（16MB の 78 回）
        let outcome = RoundOutcome(
            kind: .collected,
            plan: plan,
            budgetBytes: 2048 * megabyte,
            donatedBytes: 1248 * megabyte,
            stoppedAtSafetyLine: false
        )
        let figures = CollectFigures(outcome: outcome)
        #expect(figures.donatedMegabytes == 1248)
        #expect(figures.lineMegabytes == 1187)
        #expect(figures.excessMegabytes == 61)
    }
}

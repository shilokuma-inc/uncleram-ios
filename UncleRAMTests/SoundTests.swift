import Foundation
import Testing
@testable import UncleRAM

/// 呼ばれたことを記録するだけの偽物
private final class FakeSoundPlayer: SoundPlaying {
    enum Call: Equatable {
        case play(SoundEffect, level: Float, fadeIn: TimeInterval, delay: TimeInterval)
        case setLevel(SoundEffect, Float)
        case stop(SoundEffect, fadeOut: TimeInterval)
    }

    var calls: [Call] = []

    /// 鳴らした音（止めたものは数えない）
    var played: [SoundEffect] {
        calls.compactMap { call in
            if case let .play(effect, _, _, _) = call {
                return effect
            }
            return nil
        }
    }

    func play(_ effect: SoundEffect, level: Float, fadeIn: TimeInterval, delay: TimeInterval) {
        calls.append(.play(effect, level: level, fadeIn: fadeIn, delay: delay))
    }

    func setLevel(_ level: Float, of effect: SoundEffect, over duration: TimeInterval) {
        calls.append(.setLevel(effect, level))
    }

    func stop(_ effect: SoundEffect, fadeOut: TimeInterval) {
        calls.append(.stop(effect, fadeOut: fadeOut))
    }
}

/// 効果音を鳴らすきっかけ（docs/SPEC.md「音と振動」）と、アプリに入れた音のファイル
struct SoundTests {
    private static func outcome(_ kind: RoundOutcome.Kind) -> RoundOutcome {
        let plan = RoundPlan(isEarlyCollection: false, collectionLine: 0.6, hintThresholds: [0.45, 0.52, 0.58], bluffAt: nil)
        return RoundOutcome(kind: kind, plan: plan, budgetBytes: 2 << 30, donatedBytes: 1 << 30, stoppedAtSafetyLine: false)
    }

    /// 接近でプロペラを無音から大きくしながら鳴らし始め、警告でもう少し大きくし、離したら（解放に入ったら）小さくして止める
    @Test
    func propellerApproachesAndStopsOnRelease() {
        let player = FakeSoundPlayer()
        let sounds = RoundSounds(player: player) { false }

        sounds.phaseChanged(to: .donating)
        sounds.hintStageChanged(to: .sign)
        #expect(player.calls.isEmpty)
        sounds.hintStageChanged(to: .approach)
        sounds.hintStageChanged(to: .warning)
        sounds.phaseChanged(to: .settling)

        #expect(
            player.calls == [
                .play(.propeller, level: RoundSounds.approachLevel, fadeIn: RoundSounds.approachFadeIn, delay: 0),
                .setLevel(.propeller, RoundSounds.warningLevel),
                .stop(.propeller, fadeOut: RoundSounds.propellerFadeOut)
            ]
        )
        #expect(RoundSounds.approachLevel < RoundSounds.warningLevel)
    }

    /// 確保の 1 回で接近を飛ばして警告になったときは、警告の大きさで鳴らし始める
    @Test
    func warningWithoutApproachStartsPropeller() {
        let player = FakeSoundPlayer()
        let sounds = RoundSounds(player: player) { false }

        sounds.hintStageChanged(to: .warning)

        #expect(player.calls == [.play(.propeller, level: RoundSounds.warningLevel, fadeIn: RoundSounds.warningFade, delay: 0)])
    }

    /// 納品（と納品扱いの監査）は、結果が出たら判子とベルを鳴らし、明細が出たら少し遅らせて印字の音を 1 回だけ鳴らす
    @Test(arguments: [RoundOutcome.Kind.delivered, .audited])
    func deliveryPlaysStampThenReceipt(kind: RoundOutcome.Kind) throws {
        let player = FakeSoundPlayer()
        let sounds = RoundSounds(player: player) { false }
        let outcome = Self.outcome(kind)

        sounds.phaseChanged(to: .donating)
        sounds.phaseChanged(to: .settling)
        sounds.phaseChanged(to: .result(outcome))
        sounds.resultAppeared(outcome)
        sounds.resultAppeared(outcome)

        let delay = try #require(RoundSounds.receiptDelay(after: kind))
        #expect(player.calls == [.play(.delivered, level: 1, fadeIn: 0, delay: 0), .play(.receipt, level: 1, fadeIn: 0, delay: delay)])
        #expect(delay > 0)
    }

    /// 回収は、結果が出たら（回収演出の始まり）汽笛を鳴らし、プロペラを止める。明細は「結果を見る」のあとに出るので、すぐに印字する
    @Test
    func collectionPlaysWhistle() {
        let player = FakeSoundPlayer()
        let sounds = RoundSounds(player: player) { false }
        let outcome = Self.outcome(.collected)

        sounds.phaseChanged(to: .donating)
        sounds.hintStageChanged(to: .approach)
        sounds.phaseChanged(to: .result(outcome))
        sounds.resultAppeared(outcome)

        #expect(player.played == [.propeller, .whistle, .receipt])
        #expect(player.calls.contains(.stop(.propeller, fadeOut: RoundSounds.propellerFadeOut)))
        #expect(RoundSounds.receiptDelay(after: .collected) ?? 1 < 0.5)
    }

    /// 無効（バックグラウンド・発熱）は、鳴っている音を止め、明細の印字も鳴らさない
    @Test
    func voidedStopsEverything() {
        let player = FakeSoundPlayer()
        let sounds = RoundSounds(player: player) { false }
        let outcome = Self.outcome(.voided(.background))

        sounds.phaseChanged(to: .donating)
        sounds.hintStageChanged(to: .approach)
        sounds.phaseChanged(to: .result(outcome))
        sounds.resultAppeared(outcome)

        #expect(player.played == [.propeller])
        for effect in SoundEffect.allCases {
            #expect(player.calls.contains(.stop(effect, fadeOut: 0)))
        }
    }

    /// 次のラウンドへ進んだら（待機に戻ったら）、印字を待っているところでも取り消す。次のラウンドの明細は、また印字する
    @Test
    func nextRoundCancelsPendingReceipt() {
        let player = FakeSoundPlayer()
        let sounds = RoundSounds(player: player) { false }
        let outcome = Self.outcome(.delivered)

        sounds.phaseChanged(to: .result(outcome))
        sounds.resultAppeared(outcome)
        sounds.phaseChanged(to: .ready)
        #expect(player.calls.contains(.stop(.receipt, fadeOut: 0)))

        sounds.phaseChanged(to: .donating)
        sounds.phaseChanged(to: .result(outcome))
        sounds.resultAppeared(outcome)
        #expect(player.played == [.delivered, .receipt, .delivered, .receipt])
    }

    /// 計測のときは鳴らさない（止めるのは、ふだんどおり）
    @Test
    func silencedRoundPlaysNothing() {
        let player = FakeSoundPlayer()
        let sounds = RoundSounds(player: player) { true }
        let outcome = Self.outcome(.collected)

        sounds.phaseChanged(to: .donating)
        sounds.hintStageChanged(to: .approach)
        sounds.hintStageChanged(to: .warning)
        sounds.phaseChanged(to: .settling)
        sounds.phaseChanged(to: .result(outcome))
        sounds.resultAppeared(outcome)

        #expect(player.played.isEmpty)
    }

    /// 計測（BenchRunner）でラウンドを動かしている間は、エンジンから作った係も鳴らさない
    @Test
    func automatedEngineSilencesSounds() {
        let engine = RoundEngine(probe: SimulatedMemoryProbe(totalBytes: 2 << 30))
        let player = FakeSoundPlayer()
        let sounds = RoundSounds(player: player) { engine.isAutomated }

        engine.isAutomated = true
        sounds.hintStageChanged(to: .approach)
        #expect(player.played.isEmpty)
        engine.isAutomated = false
        sounds.hintStageChanged(to: .approach)
        #expect(player.played == [.propeller])
    }

    /// アプリに入れた音が、すべて読み込める。プロペラはループにするので、接近から回収まで（1〜2 秒）より十分に長い
    @Test
    func bundledSoundsLoad() throws {
        let bank = SoundBank()
        bank.load()

        #expect(bank.loadedEffects == Set(SoundEffect.allCases))
        #expect(try #require(bank.duration(of: .propeller)) >= 4)
        for effect in [SoundEffect.delivered, .whistle, .receipt] {
            #expect(try #require(bank.duration(of: effect)) < 3.5)
        }
    }

    /// 音は圧縮して小さく保つ（docs/SPEC.md「音と振動」の上限は合計 20MB。効果音だけなら 1MB 前後を目安にする）
    @Test
    func bundledSoundsAreSmall() throws {
        var total = 0
        for effect in SoundEffect.allCases {
            let url = try #require(Bundle.main.url(forResource: effect.rawValue, withExtension: "m4a"))
            total += try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        }
        #expect(total < 1_000_000)
    }
}

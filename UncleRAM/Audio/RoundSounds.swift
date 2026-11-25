import Foundation

/// ラウンドの出来事から、効果音を鳴らすきっかけを決める（docs/SPEC.md「音と振動」）。RoundScreen の `onChange` から呼ぶ。
///
/// - 接近（ヒントの 2 段階目）でプロペラを鳴らし始めて大きくしていき、警告（3 段階目）でもう少し大きくする。
///   はったり（偽の気配）はヒントの段階を変えないので、プロペラは鳴らない
/// - 離したら（確保を止めて解放に入ったら）プロペラを止め、全メモリを解放して結果が出てから、納品・回収の音を鳴らす
/// - 結果（明細書）が画面に出たら、印字の音を鳴らす。納品のときは、判子とベルのあとに続ける
/// - 計測（`RoundEngine.isAutomated`）と撮影モードでは鳴らさない。練習ラウンドと「視差効果を減らす」では、ふだんどおり鳴らす
///
/// 音のヒントは、画面の印でも同時に出す（docs/SPEC.md「アクセシビリティ」）。プロペラを鳴らすきっかけの `RoundEngine.hintStage` で、
/// 回収飛行船が大きくなり、ヒントの欄が「回収飛行船 接近」になる
final class RoundSounds {
    /// プロペラの大きさ（`SoundEffect.mixLevel` に対する割合）
    static let approachLevel: Float = 0.6
    static let warningLevel: Float = 1
    /// 接近で、無音からこの秒数をかけて大きくする（近づいてくるように）。接近から回収まではおよそ 1〜2 秒
    static let approachFadeIn: TimeInterval = 1.2
    /// 警告で、この秒数をかけてもう少し大きくする
    static let warningFade: TimeInterval = 0.3
    /// 離したときに、この秒数で小さくして止める（ぶつりと切れないように）
    static let propellerFadeOut: TimeInterval = 0.15

    private let player: any SoundPlaying
    private let isSilenced: () -> Bool
    private var isPropellerPlaying = false
    /// このラウンドの明細の印字を、もう鳴らしたか（結果の画面が出直しても、2 回鳴らさない）
    private var hasPrintedReceipt = false

    init(player: any SoundPlaying = SoundBank.shared, isSilenced: @escaping () -> Bool) {
        self.player = player
        self.isSilenced = isSilenced
    }

    /// 計測と撮影モードでは鳴らさない
    convenience init(engine: RoundEngine) {
        self.init { [weak engine] in
            ScreenshotDemo.isEnabled || engine?.isAutomated ?? true
        }
    }

    func hintStageChanged(to stage: RoundPlan.HintStage) {
        guard !isSilenced() else {
            return
        }
        switch stage {
        case .approach:
            startPropeller(level: Self.approachLevel, fadeIn: Self.approachFadeIn)
        case .warning:
            // 確保の 1 回で 2 段階目を飛ばしたとき（枠の小さい端末など）は、ここから鳴らし始める
            if isPropellerPlaying {
                player.setLevel(Self.warningLevel, of: .propeller, over: Self.warningFade)
            } else {
                startPropeller(level: Self.warningLevel, fadeIn: Self.warningFade)
            }
        case .none, .sign:
            break
        }
    }

    func phaseChanged(to phase: RoundEngine.Phase) {
        switch phase {
        case .donating:
            hasPrintedReceipt = false
        case .settling:
            stopPropeller()
        case let .result(outcome):
            stopPropeller()
            guard !isSilenced() else {
                return
            }
            switch outcome.kind {
            case .delivered, .audited:
                // 監査も納品扱い（判子を押して結果を出す）なので、納品と同じ音にする
                player.play(.delivered, level: 1, fadeIn: 0, delay: 0)
            case .collected:
                player.play(.whistle, level: 1, fadeIn: 0, delay: 0)
            case .voided:
                // 納品のあとで無効に変わったとき（inactive で離して、そのまま裏に回った）は、鳴っている音も止める
                stopAll()
            }
        case .ready, .unavailable:
            // 次のラウンド・遊べないとき。印字を待っているところなら取り消す
            stopAll()
        }
    }

    /// 結果（明細書）が画面に出た
    func resultAppeared(_ outcome: RoundOutcome) {
        guard !isSilenced(), !hasPrintedReceipt, let delay = Self.receiptDelay(after: outcome.kind) else {
            return
        }
        hasPrintedReceipt = true
        player.play(.receipt, level: 1, fadeIn: 0, delay: delay)
    }

    /// 結果が出てから、明細の印字を鳴らすまでの秒数。無効は明細を出さないので鳴らさない
    static func receiptDelay(after kind: RoundOutcome.Kind) -> TimeInterval? {
        switch kind {
        case .delivered, .audited:
            // 結果と同時に鳴る判子とベル（約 1 秒）の、ベルの余韻に重ねる
            0.6
        case .collected:
            // 結果が出るのは、回収演出の「結果を見る」を押したあとなので、すぐに鳴らす
            0.1
        case .voided:
            nil
        }
    }

    /// ラウンドの画面を離れたとき
    func stopAll() {
        isPropellerPlaying = false
        player.stopAll()
    }

    private func startPropeller(level: Float, fadeIn: TimeInterval) {
        isPropellerPlaying = true
        player.play(.propeller, level: level, fadeIn: fadeIn, delay: 0)
    }

    private func stopPropeller() {
        guard isPropellerPlaying else {
            return
        }
        isPropellerPlaying = false
        player.stop(.propeller, fadeOut: Self.propellerFadeOut)
    }
}

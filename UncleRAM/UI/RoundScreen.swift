import SwiftUI

/// 速達便のラウンド画面と結果。横幅で、iPhone のレイアウトと Mac の横長のレイアウトを切り替える
/// （iPad は広いときは横長、Split View などで狭いときは iPhone のレイアウト。2026-11-12 にユーザーが決定）。
struct RoundScreen: View {
    /// これより広いときは横長のレイアウトにする（Mac のデザインの最小幅 1000 に近い値）
    static let wideLayoutMinimumWidth: CGFloat = 960

    @State private var engine: RoundEngine
    @State private var monitor: RoundEventMonitor
    @State private var bench: BenchRunner
    /// 最初の 1 回で覚えることの吹き出し
    @State private var coach = TutorialCoach()
    /// 「?」から開く遊び方の 3 コマ
    @State private var showsHowToPlay = false
    /// 効果音を鳴らすきっかけ（計測のときは鳴らさない）
    @State private var sounds: RoundSounds
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LocalStore.self) private var store: LocalStore?
    /// 回収演出の「結果を見る」を押したか。結果の段階を出たら（次のラウンド・タイトル）戻す。
    /// 撮影モードの `collected` は、回収演出の先の結果の画面を撮る
    @State private var revealsResult = ScreenshotDemo.scene == .collected
    /// 結果からタイトルへ戻る。nil のときは「タイトルへ」を出さない
    private let onExit: (() -> Void)?

    init(engine: RoundEngine = RoundEngine(), onExit: (() -> Void)? = nil) {
        self.onExit = onExit
        _engine = State(initialValue: engine)
        _monitor = State(initialValue: RoundEventMonitor(engine: engine))
        _bench = State(initialValue: BenchRunner(engine: engine))
        _sounds = State(initialValue: RoundSounds(engine: engine))
    }

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= Self.wideLayoutMinimumWidth
            ZStack {
                PaperBackground(wide: wide)
                content(wide: wide, size: proxy.size)
                if engine.hintStage == .warning, engine.phase == .donating {
                    // 練習ラウンドでは兆しを大きく出す（ノイズを濃くする）
                    InkNoise(intensity: engine.plan?.isPractice == true ? 1.6 : 1).ignoresSafeArea()
                }
                if showsHowToPlay {
                    HowToPlayOverlay(wide: wide) { showsHowToPlay = false }
                        .transition(.opacity)
                }
            }
        }
        .overlay(alignment: .bottom) {
            BenchStatusBar(bench: bench)
        }
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.2), value: showsHowToPlay)
        .environment(coach)
        .onAppear {
            if let scene = ScreenshotDemo.scene {
                engine.showDemo(scene)
                return
            }
            // 計測で起動したときは、吹き出しを出さず、練習ラウンドにもしない
            if !BenchRunner.isRequestedByLaunchArguments {
                coach.store = store
            }
            engine.isPracticeRound = !(store?.hasCompletedFirstRound ?? true)
            monitor.tapToDonate = store?.tapToDonate ?? false
            monitor.start()
            bench.startFromLaunchArgumentsIfNeeded()
        }
        .onDisappear {
            // 画面が消えたら（Mac でウィンドウを閉じたときなど）、計測も止める。止めないと、画面も監視も無いまま確保を続けてしまう
            bench.cancel()
            monitor.stop()
            sounds.stopAll()
        }
        .onChange(of: engine.hintStage) { _, stage in
            sounds.hintStageChanged(to: stage)
            if let bubble = TutorialBubble.forHintStage(stage), !engine.isAutomated {
                coach.reveal(bubble)
            }
        }
        .onChange(of: engine.bluff) { _, bluff in
            if bluff == .grinning, !engine.isAutomated {
                coach.reveal(.bluff)
            }
        }
        .onChange(of: engine.phase) { _, phase in
            sounds.phaseChanged(to: phase)
            guard case let .result(outcome) = phase else {
                // 結果の段階を出たら（次のラウンド・タイトル）、回収演出の「結果を見る」を戻す
                revealsResult = false
                return
            }
            coach.dismiss()
            // 練習ラウンドを終えたら、次から普段のラウンドにする（無効になったときは、もう一度練習にする）
            if let completed = Self.practiceCompletion(after: outcome) {
                store?.hasCompletedFirstRound = completed
            }
            engine.isPracticeRound = !(store?.hasCompletedFirstRound ?? true)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .inactive:
                engine.endHold(.inactive)
            case .background:
                engine.void(.background)
                bench.appDidEnterBackground()
            case .active:
                engine.sceneBecameActive()
            @unknown default:
                break
            }
        }
    }

    /// 練習ラウンドの結果のあと、「練習を終えた」をどうするか。練習ラウンドでなければ nil（変えない）。
    /// 納品のあとで同じ結果が無効に変わる（inactive で離したあと、そのまま裏に回った）ときも結果が届くので、
    /// そのときは、いったん記録した「練習を終えた」を取り消す（次も練習にする）
    static func practiceCompletion(after outcome: RoundOutcome) -> Bool? {
        guard outcome.plan.isPractice else {
            return nil
        }
        if case .voided = outcome.kind {
            return false
        }
        return true
    }

    @ViewBuilder
    private func content(wide: Bool, size: CGSize) -> some View {
        switch engine.phase {
        // 回収されたら、結果の前に回収演出を出す。監査（納品扱い）と無効（店じまい）には出さない（docs/SPEC.md「ラウンドの状態と中断」）。
        // 計測中は出さない（次のラウンドまでの間に演出を描いて、落ちたフレームの計測を乱さないように）
        case let .result(outcome) where outcome.kind == .collected && !revealsResult && !engine.isAutomated:
            CollectEffect(outcome: outcome, wide: wide) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    revealsResult = true
                }
                // 早期回収で初めて回収されたときの吹き出しは、結果の「抜き打ち回収」の判子の横に出すので、結果に進んでから出す
                if outcome.plan.isEarlyCollection {
                    coach.reveal(.earlyCollection)
                }
            }
            .transition(.opacity)
        case let .result(outcome):
            ResultView(
                outcome: outcome,
                releaseDuration: engine.lastReleaseDuration,
                wide: wide,
                onRetry: { engine.reset() },
                onExit: onExit
            )
            .onAppear { sounds.resultAppeared(outcome) }
        default:
            if wide {
                WideRoundLayout(engine: engine, bench: bench) { showsHowToPlay = true }
            } else {
                CompactRoundLayout(engine: engine, bench: bench, height: size.height) { showsHowToPlay = true }
                    .frame(maxWidth: 480)
            }
        }
    }
}

/// 会長の台詞と、シルクハットが傾いているか
enum ChairmanLines {
    static func line(for engine: RoundEngine) -> LocalizedStringKey {
        switch engine.phase {
        case .ready, .unavailable:
            return "その RAM、ほとんど\n使われていませんよね？"
        case .donating, .settling, .result:
            break
        }
        switch engine.bluff {
        case .showing:
            return "……ほう。\nずいぶん気前がいい。"
        case .grinning:
            return "……なんてな。"
        case .none:
            break
        }
        switch engine.hintStage {
        case .none:
            return "効率化へのご協力、\n心より感謝申し上げます。"
        case .sign:
            return "……ほう。\nずいぶん気前がいい。"
        case .approach, .warning:
            return "あと少しだけ、\nあと少しだけですので。"
        }
    }

    static func isLeaning(_ engine: RoundEngine) -> Bool {
        engine.bluff == .showing || (engine.bluff == .none && engine.hintStage >= .sign)
    }

    /// はったりのときは、ヒントの欄にも偽の気配を出す
    static func displayedStage(_ engine: RoundEngine) -> RoundPlan.HintStage {
        engine.bluff == .showing ? .sign : engine.hintStage
    }
}

/// 長押しで献上・離すと納品のボタン（指・クリック）。タッチのキャンセルも離したとみなす。
/// 設定「タップで献上」のときは、1 回目のタップで始め、もう一度タップすると納品する
struct HoldButton: View {
    let engine: RoundEngine
    var diameter: CGFloat = 200
    /// 設定。撮影モードやプレビューなど、AppRoot の外で使うときは無い
    @Environment(LocalStore.self) private var store: LocalStore?

    private var tapToDonate: Bool {
        store?.tapToDonate ?? false
    }

    var body: some View {
        gesture(HoldButtonFace(holding: engine.phase == .donating, diameter: diameter, tapToDonate: tapToDonate))
            .disabled(engine.isAutomated || !(engine.phase == .ready || engine.phase == .donating))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("献上する"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                guard !engine.isAutomated else {
                    return
                }
                // VoiceOver はダブルタップで開始、もう一度で納品（タップ操作と同じ。docs/SPEC.md「アクセシビリティ」）
                engine.toggleDonation()
            }
    }

    @ViewBuilder
    private func gesture(_ face: HoldButtonFace) -> some View {
        if tapToDonate {
            face
                .contentShape(Circle())
                .onTapGesture { engine.toggleDonation() }
        } else {
            face
                .contentShape(Circle())
                .onLongPressGesture(
                    minimumDuration: .infinity,
                    maximumDistance: .infinity,
                    perform: {},
                    onPressingChanged: { pressing in
                        if pressing {
                            engine.beginHold()
                        } else {
                            engine.endHold(.released)
                        }
                    }
                )
        }
    }
}

/// 遊べないときの案内
struct UnavailableNotice: View {
    let reason: RoundEngine.Unavailability

    var body: some View {
        VStack(spacing: 8) {
            switch reason {
            case let .budgetTooSmall(bytes):
                Text("いまは空きメモリが足りません")
                    .scaledFont(.mincho(17))
                Text("枠 \(Formatters.megabytes(bytes)) MB。ほかのアプリを閉じてから、もう一度お試しください。")
                    .scaledFont(.mincho(13, .medium))
            case .thermal:
                Text("データセンターも大変なんです")
                    .scaledFont(.mincho(17))
                Text("端末が熱くなっています。少し休んでから、もう一度お試しください。")
                    .scaledFont(.mincho(13, .medium))
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.navy)
        .padding(20)
        .doubleFrame()
    }
}

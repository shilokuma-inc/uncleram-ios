import SwiftUI

/// 速達便のラウンド画面と結果。横幅で、iPhone のレイアウトと Mac の横長のレイアウトを切り替える
/// （iPad は広いときは横長、Split View などで狭いときは iPhone のレイアウト。2026-11-12 にユーザーが決定）。
struct RoundScreen: View {
    /// これより広いときは横長のレイアウトにする（Mac のデザインの最小幅 1000 に近い値）
    static let wideLayoutMinimumWidth: CGFloat = 960

    @State private var engine: RoundEngine
    @State private var monitor: RoundEventMonitor
    @State private var bench: BenchRunner
    @Environment(\.scenePhase) private var scenePhase

    init(engine: RoundEngine = RoundEngine()) {
        _engine = State(initialValue: engine)
        _monitor = State(initialValue: RoundEventMonitor(engine: engine))
        _bench = State(initialValue: BenchRunner(engine: engine))
    }

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= Self.wideLayoutMinimumWidth
            ZStack {
                PaperBackground(wide: wide)
                content(wide: wide, size: proxy.size)
                if engine.hintStage == .warning, engine.phase == .donating {
                    InkNoise().ignoresSafeArea()
                }
            }
        }
        .overlay(alignment: .bottom) {
            BenchStatusBar(bench: bench)
        }
        .preferredColorScheme(.light)
        .onAppear {
            monitor.start()
            bench.startFromLaunchArgumentsIfNeeded()
        }
        .onDisappear { monitor.stop() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .inactive:
                engine.endHold(.inactive)
            case .background:
                engine.void(.background)
            case .active:
                engine.refreshBudget()
            @unknown default:
                break
            }
        }
    }

    @ViewBuilder
    private func content(wide: Bool, size: CGSize) -> some View {
        switch engine.phase {
        case let .result(outcome):
            ResultView(outcome: outcome, releaseDuration: engine.lastReleaseDuration, wide: wide) {
                engine.reset()
            }
        default:
            if wide {
                WideRoundLayout(engine: engine, bench: bench)
            } else {
                CompactRoundLayout(engine: engine, bench: bench, height: size.height)
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

/// 長押しで献上・離すと納品のボタン（指・クリック）。タッチのキャンセルも離したとみなす
struct HoldButton: View {
    let engine: RoundEngine
    var diameter: CGFloat = 200
    var title: LocalizedStringKey = "長押しで献上"

    var body: some View {
        HoldButtonFace(holding: engine.phase == .donating, diameter: diameter, title: title)
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
            .disabled(!(engine.phase == .ready || engine.phase == .donating))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("献上する"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                // VoiceOver はダブルタップで開始、もう一度で納品（タップ操作と同じ。docs/SPEC.md「アクセシビリティ」）
                if engine.phase == .donating {
                    engine.endHold(.released)
                } else {
                    engine.beginHold()
                }
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
                    .font(Theme.mincho(17))
                Text("枠 \(Formatters.megabytes(bytes)) MB。ほかのアプリを閉じてから、もう一度お試しください。")
                    .font(Theme.mincho(13, bold: false))
            case .thermal:
                Text("データセンターも大変なんです")
                    .font(Theme.mincho(17))
                Text("端末が熱くなっています。少し休んでから、もう一度お試しください。")
                    .font(Theme.mincho(13, bold: false))
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.navy)
        .padding(20)
        .doubleFrame()
    }
}

import SwiftUI

/// 速達便の結果。ゲージに回収ラインと離した位置を並べて明かす
/// （負けた理由も、もう少し押せたかも一目で分かるように。docs/SPEC.md「説明なしで分かる UI」）。
/// iPhone（と、iPad の縦向きや狭い幅）は docs/design/Reveal.png、Mac と広い iPad は MacReveal.png（1200 × 760）に合わせる。
/// 文字を大きくして（Dynamic Type）収まらないときは、縦に送れるようにする。収まるときは、ボタンを画面の下に寄せる
struct ResultView: View {
    let outcome: RoundOutcome
    /// 全解放にかかった秒数（計測のために小さく出す）
    let releaseDuration: TimeInterval?
    let wide: Bool
    let onRetry: () -> Void
    /// タイトルへ戻る。nil のときは出さない
    var onExit: (() -> Void)?
    @Environment(\.roundMode) private var mode
    /// 共有のプレビューを開いているか。iPad を回して組み方が変わっても閉じないよう、組み方の外に持つ
    @State private var sharesStatement = false

    /// デイリーは、その日のうちは回収ラインの位置を明かさない（「納品」「回収」とニアミスの判子だけ）
    private var revealsLine: Bool {
        mode.revealsCollectionLine()
    }

    /// 無効になったラウンド（店じまい）か
    private var isVoided: Bool {
        if case .voided = outcome.kind {
            return true
        }
        return false
    }

    /// 「明細書をシェア」で載せるモード（速達便か、その日のデイリーか）
    private var shareMode: ShareSummary.Mode {
        mode.daily.map { .init(daily: $0) } ?? .express
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                if wide {
                    wideLayout(minHeight: proxy.size.height)
                } else {
                    compactLayout(minHeight: proxy.size.height)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(Theme.navy)
        .sheet(isPresented: $sharesStatement) {
            if let shareSummary {
                SharePreviewScreen(summary: shareSummary)
            }
        }
    }

    /// シェアに載せる結果。無効になったラウンド（店じまい）はシェアしない
    private var shareSummary: ShareSummary? {
        ShareSummary(outcome: outcome, mode: shareMode)
    }

    // MARK: - iPhone（Reveal.png）

    private func compactLayout(minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            compactHeader
            Ornament()
            switch outcome.kind {
            case .voided:
                voidedNotice
            default:
                ResultRevealCard(outcome: outcome, revealsLine: revealsLine, metrics: .compact)
                ResultChairmanBubble(outcome: outcome, revealsLine: revealsLine, metrics: .compact)
                compactFigures
            }
            Spacer(minLength: 24)
            actions
            if releaseDuration != nil {
                releaseNote
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }

    private var compactHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(mode.resultTitle)
                    .scaledFont(.mincho(13))
                    .foregroundStyle(Theme.subText)
                Text("取引先: \(Client.allocateCorp.name)")
                    .scaledFont(.mincho(16))
            }
            Spacer()
            if let stamp {
                CircleStamp(text: stamp, diameter: 78)
                    .accessibilityLabel(Text(stamp))
                    .tutorialBubble([.earlyCollection], edge: .bottom, alignment: .trailing)
            }
        }
    }

    private var compactFigures: some View {
        VStack(spacing: 12) {
            figureRow("献上量", "\(Formatters.megabytes(outcome.donatedBytes)) MB", titleSize: 17, valueFont: Theme.display(24))
            figureRow("ニアミス倍率", "×\(outcome.nearMissMultiplierText)", titleSize: 17, valueFont: Theme.display(15))
            DashedRule()
            scoreRow(titleSize: 17, valueSize: 34)
        }
        .padding(.top, 8)
    }

    // MARK: - Mac と広い iPad（MacReveal.png）

    /// 左に判子と会長、中央にゲージ、右に数字とボタン。広げると中央の列が伸びる
    private func wideLayout(minHeight: CGFloat) -> some View {
        VStack(spacing: 14) {
            wideHeader
            Ornament()
            HStack(alignment: .top, spacing: 32) {
                wideLeftColumn
                    .frame(width: 280, alignment: .leading)
                // デザインでは、ゲージの欄は列の高さの中ほどに置く
                Group {
                    switch outcome.kind {
                    case .voided:
                        voidedNotice
                    default:
                        ResultRevealCard(outcome: outcome, revealsLine: revealsLine, metrics: .wide)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                wideRightColumn
                    .frame(width: 300)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            wideFooter
        }
        .padding(.horizontal, 36)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .frame(minHeight: minHeight)
    }

    private var wideHeader: some View {
        HStack {
            CorporateMasthead()
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 28) {
                Text(mode.resultTitle)
                    .scaledFont(.typewriter(12))
                    .tracking(1)
                    .foregroundStyle(Theme.subText)
                Text("取引先: \(Client.allocateCorp.name)")
                    .scaledFont(.mincho(15))
            }
        }
    }

    private var wideLeftColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let stamp {
                CircleStamp(text: stamp, diameter: 96, angle: .degrees(-12))
                    .accessibilityLabel(Text(stamp))
                    // 判子は左の列にあるので、吹き出しは判子の左の端から右へ出す
                    .tutorialBubble([.earlyCollection], edge: .bottom, alignment: .leading)
                    .padding(.top, 6)
                    .padding(.leading, 10)
            }
            if !isVoided {
                ResultChairmanBubble(outcome: outcome, revealsLine: revealsLine, metrics: .wide)
            }
        }
    }

    private var wideRightColumn: some View {
        VStack(spacing: 16) {
            if !isVoided {
                VStack(spacing: 10) {
                    figureRow("献上量", "\(Formatters.megabytes(outcome.donatedBytes)) MB", titleSize: 15, valueFont: Theme.display(18))
                    figureRow("ニアミス倍率", "×\(outcome.nearMissMultiplierText)", titleSize: 15, valueFont: Theme.typewriter(15))
                    DashedRule()
                    scoreRow(titleSize: 15, valueSize: 26)
                }
                .padding(20)
                .doubleFrame()
            }
            Spacer(minLength: 24)
            actions
        }
    }

    /// 下の破線の帯。左に解放の時間、右に Mac のキーボードの操作
    private var wideFooter: some View {
        HStack(alignment: .firstTextBaseline) {
            releaseNote
            Spacer()
            #if os(macOS)
            Text(keyboardHint)
                .scaledFont(.typewriter(12))
                .foregroundStyle(Theme.subText)
            #endif
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { DashedRule() }
    }

    #if os(macOS)
    /// ボタンに付けたキー（return・⌘S・esc）。デザインは「return: もう一度 · ⌘S: シェア」
    private var keyboardHint: LocalizedStringKey {
        let shares = shareSummary != nil
        if mode.daily != nil, onExit != nil {
            return shares ? "return: タイトルへ · ⌘S: シェア" : "return: タイトルへ"
        }
        switch (shares, onExit != nil) {
        case (true, true):
            return "return: もう一度 · ⌘S: シェア · esc: タイトルへ"
        case (true, false):
            return "return: もう一度 · ⌘S: シェア"
        case (false, true):
            return "return: もう一度 · esc: タイトルへ"
        case (false, false):
            return "return: もう一度"
        }
    }
    #endif

    // MARK: - 共通の部品

    private var stamp: LocalizedStringKey? {
        switch outcome.kind {
        case .delivered:
            "納品"
        case .collected:
            outcome.plan.isEarlyCollection ? "抜き打ち\n回収" : "回収"
        case .audited:
            "監査"
        case .voided:
            nil
        }
    }

    private func figureRow(_ title: LocalizedStringKey, _ value: String, titleSize: CGFloat, valueFont: Font) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .scaledFont(.mincho(titleSize))
            Spacer()
            Text(verbatim: value)
                .font(valueFont)
        }
    }

    private func scoreRow(titleSize: CGFloat, valueSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("スコア")
                .scaledFont(.mincho(titleSize, .extraBold))
                .tracking(titleSize * 0.1)
            Spacer()
            Text(verbatim: "\(Formatters.integer(outcome.score)) pt")
                .font(Theme.display(valueSize))
                .foregroundStyle(Theme.red)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// 「明細書をシェア」「もう一度献上する」「タイトルへ」。デイリーは 1 日 1 回なので「もう一度」は出さない。
    /// Mac は ⌘S でシェア、return で主な操作（もう一度・デイリーはタイトルへ）、esc でタイトルへ
    private var actions: some View {
        VStack(spacing: 14) {
            if shareSummary != nil {
                // デザイン（Reveal.png・MacReveal.png）どおり、主ボタンを「明細書をシェア」にする
                PrimaryInkButton(title: "明細書をシェア", fontSize: 17, verticalPadding: 15) { sharesStatement = true }
                    .keyboardShortcut("s", modifiers: .command)
            }
            if mode.daily != nil, let onExit {
                // デイリーは 1 日 1 回なので、もう一度はできない
                if shareSummary != nil {
                    RuleButton(title: "タイトルへ", action: onExit)
                        .keyboardShortcut(.defaultAction)
                } else {
                    PrimaryInkButton(title: "タイトルへ", action: onExit)
                        .keyboardShortcut(.defaultAction)
                }
            } else if shareSummary != nil {
                RuleButton(title: "もう一度献上する", action: onRetry)
                    .keyboardShortcut(.defaultAction)
            } else {
                PrimaryInkButton(title: "もう一度献上する", action: onRetry)
                    .keyboardShortcut(.defaultAction)
            }
            if mode.daily == nil, let onExit {
                // ラウンドの途中には置かない（結果のときだけ）。Mac は esc でも戻れる
                TextLink(title: "タイトルへ", action: onExit)
                    .keyboardShortcut(.cancelAction)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private var releaseNote: some View {
        if let releaseDuration {
            Text("解放 \(Int((releaseDuration * 1000).rounded())) ms")
                .scaledFont(.typewriter(11))
                .foregroundStyle(Theme.subText)
        }
    }

    private var voidedNotice: some View {
        Text("店じまいしました")
            .scaledFont(.mincho(22))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .doubleFrame(inset: 8)
    }
}

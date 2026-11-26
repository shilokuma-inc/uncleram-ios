import SwiftUI

/// 速達便の結果。ゲージに回収ラインと離した位置を並べて明かす
/// （負けた理由も、もう少し押せたかも一目で分かるように。docs/SPEC.md「説明なしで分かる UI」）。
/// docs/design/Reveal.png に合わせる（Mac と広い iPad も、今は同じ形を中央に置く）。
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
    /// 共有のプレビューを開いているか
    @State private var sharesStatement = false

    /// デイリーは、その日のうちは回収ラインの位置を明かさない（「納品」「回収」とニアミスの判子だけ）
    private var revealsLine: Bool {
        mode.revealsCollectionLine()
    }

    /// 「明細書をシェア」で載せるモード（速達便か、その日のデイリーか）
    private var shareMode: ShareSummary.Mode {
        mode.daily.map { .init(daily: $0) } ?? .express
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                compactLayout(minHeight: proxy.size.height)
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

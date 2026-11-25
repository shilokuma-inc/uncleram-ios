import SwiftUI

/// 速達便の結果。docs/design/Reveal.png に合わせ、ゲージに回収ラインと離した位置を並べて明かす
/// （負けた理由も、もう少し押せたかも一目で分かるように。docs/SPEC.md「説明なしで分かる UI」）
struct ResultView: View {
    let outcome: RoundOutcome
    /// 全解放にかかった秒数（計測のために小さく出す）
    let releaseDuration: TimeInterval?
    let wide: Bool
    let onRetry: () -> Void
    /// タイトルへ戻る。nil のときは出さない
    var onExit: (() -> Void)?
    @Environment(\.roundMode) private var mode

    /// デイリーは、その日のうちは回収ラインの位置を明かさない（「納品」「回収」とニアミスの判子だけ）
    private var revealsLine: Bool {
        mode.revealsCollectionLine()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Ornament()
                switch outcome.kind {
                case .voided:
                    voidedNotice
                default:
                    reveal
                    chairmanBubble
                    figures
                }
                Spacer(minLength: 24)
                if mode.daily != nil, let onExit {
                    // デイリーは 1 日 1 回なので、もう一度はできない
                    PrimaryInkButton(title: "タイトルへ", action: onExit)
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
                if let releaseDuration {
                    Text("解放 \(Int((releaseDuration * 1000).rounded())) ms")
                        .scaledFont(.typewriter(11))
                        .foregroundStyle(Theme.subText)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(Theme.navy)
    }

    private var header: some View {
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

    private var reveal: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(revealsLine ? "今回の献上と回収ライン" : "今回の献上（回収ラインは明日お知らせします）")
                .scaledFont(.mincho(12))
                .foregroundStyle(Theme.subText)
            RevealGauge(released: outcome.releasedFill, line: revealsLine ? outcome.plan.collectionLine : nil)
                .padding(.vertical, 26)
            DashedRule()
            HStack(alignment: .center) {
                // 「あと ○%！」はラインまでの距離が分かるので、明かさないときは出さない
                if revealsLine {
                    gapText
                }
                Spacer()
                if outcome.nearMissMultiplier > 1 {
                    BoxStamp(caption: "ニアミス", value: "×\(multiplierText)")
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .doubleFrame(inset: 8)
    }

    @ViewBuilder private var gapText: some View {
        let gap = Formatters.percent(abs(outcome.gapToLine))
        if outcome.isSuccessful {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("あと")
                    .scaledFont(.mincho(15, .extraBold))
                Text(verbatim: "\(gap)%")
                    .font(Theme.display(40))
                    .foregroundStyle(Theme.red)
                Text(verbatim: "！")
                    .scaledFont(.mincho(15, .extraBold))
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "\(gap)%")
                    .font(Theme.display(40))
                    .foregroundStyle(Theme.red)
                Text("越えた")
                    .scaledFont(.mincho(15, .extraBold))
            }
        }
    }

    private var multiplierText: String {
        outcome.nearMissMultiplier == outcome.nearMissMultiplier.rounded()
            ? String(Int(outcome.nearMissMultiplier))
            : outcome.nearMissMultiplier.formatted(.number.precision(.fractionLength(1)))
    }

    private var chairmanLine: LocalizedStringKey {
        switch outcome.kind {
        case .collected:
            "ご提供いただいた全メモリは、当社が責任をもって有効活用いたします。"
        case .audited:
            "監査が入りました。"
        case .delivered, .voided:
            // デイリーは、その日のうちはラインを明かさない（答えは翌日、タイトルの「昨日の回収ライン」で見せる）
            revealsLine ? "ラインはここだった" : "ラインは明日、お教えしましょう"
        }
    }

    private var chairmanBubble: some View {
        HStack(spacing: 6) {
            ChairmanHat(leaning: false, size: CGSize(width: 54, height: 36))
            Text(chairmanLine)
                .scaledFont(.mincho(16))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { InkSurface() }
                .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1.5) }
                .background {
                    Rectangle().fill(Theme.navy).offset(x: 4, y: 4)
                }
        }
    }

    private var figures: some View {
        VStack(spacing: 12) {
            figureRow("献上量", "\(Formatters.megabytes(outcome.donatedBytes)) MB")
            figureRow("ニアミス倍率", "×\(multiplierText)", small: true)
            DashedRule()
            HStack(alignment: .firstTextBaseline) {
                Text("スコア")
                    .scaledFont(.mincho(17, .extraBold))
                Spacer()
                Text(verbatim: "\(Formatters.integer(outcome.score)) pt")
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.red)
            }
        }
        .padding(.top, 8)
    }

    private func figureRow(_ title: LocalizedStringKey, _ value: String, small: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .scaledFont(.mincho(17))
            Spacer()
            Text(verbatim: value)
                .font(Theme.display(small ? 15 : 24))
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

/// 結果のゲージ。離した位置（▼）と回収ライン（▲）を並べる
struct RevealGauge: View {
    let released: Double
    /// 回収ライン。nil なら描かない（デイリーのその日のうち）
    let line: Double?

    private var accessibilityText: Text {
        if let line {
            Text("離した位置は枠の \(Formatters.percent(released))%、回収ラインは \(Formatters.percent(line))%")
        } else {
            Text("離した位置は枠の \(Formatters.percent(released))%")
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                InkSurface()
                InkSurface(color: Theme.red)
                    .frame(width: max(0, (width - 8) * min(released, 1)))
                    .padding(4)
            }
            .frame(height: 42)
            .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1.5) }
            .overlay(alignment: .leading) {
                if let line {
                    Rectangle()
                        .fill(Theme.navy)
                        .frame(width: 3, height: 56)
                        .offset(x: width * line - 1.5)
                }
            }
            .overlay {
                marker(text: "離した \(Formatters.percent(released))%", symbol: "▼", color: Theme.navy, above: true)
                    .position(x: width * min(released, 1), y: -18)
            }
            .overlay {
                if let line {
                    marker(text: "回収ライン \(Formatters.percent(line))%", symbol: "▲", color: Theme.red, above: false)
                        .position(x: width * line, y: 42 + 18)
                }
            }
        }
        .frame(height: 42)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private func marker(text: LocalizedStringKey, symbol: String, color: Color, above: Bool) -> some View {
        VStack(spacing: 2) {
            if above {
                Text(text).scaledFont(.mincho(13, .extraBold))
                Text(verbatim: symbol).font(.system(size: 12))
            } else {
                Text(verbatim: symbol).font(.system(size: 12))
                Text(text).scaledFont(.mincho(13, .extraBold))
            }
        }
        .foregroundStyle(color)
        .fixedSize()
    }
}

import SwiftUI

/// 結果のゲージの欄（今回の献上と回収ライン・あと ○%・ニアミスの判子）
struct ResultRevealCard: View {
    let outcome: RoundOutcome
    /// 回収ラインを明かすか。デイリーは、その日のうちは明かさない
    let revealsLine: Bool
    let metrics: ResultMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.cardSpacing) {
            Text(revealsLine ? "今回の献上と回収ライン" : "今回の献上（回収ラインは明日お知らせします）")
                .scaledFont(.mincho(12))
                .foregroundStyle(Theme.subText)
                .fixedSize(horizontal: false, vertical: true)
            RevealGauge(
                released: outcome.releasedFill,
                line: revealsLine ? outcome.plan.collectionLine : nil,
                barHeight: metrics.gaugeBarHeight,
                lineOverhang: metrics.gaugeLineOverhang,
                markerSize: metrics.gaugeMarkerSize
            )
            .padding(.vertical, metrics.gaugePadding)
            DashedRule()
            // 横に並ばないとき（Split View の狭い幅や、文字を大きくしたとき）は、判子を下に送る（「○%」を折り返さない）
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    gapAndStamp(horizontal: true)
                }
                VStack(alignment: .leading, spacing: 10) {
                    gapAndStamp(horizontal: false)
                }
            }
        }
        .padding(.horizontal, metrics.cardHorizontalPadding)
        .padding(.vertical, metrics.cardVerticalPadding)
        .doubleFrame(inset: metrics.cardInset)
    }

    /// 横に並べるときは、間を空けて判子を右に寄せる
    @ViewBuilder private func gapAndStamp(horizontal: Bool) -> some View {
        // 「あと ○%！」はラインまでの距離が分かるので、明かさないときは出さない
        if revealsLine {
            gapText
                .fixedSize()
        }
        if horizontal {
            Spacer(minLength: 12)
        }
        if outcome.nearMissMultiplier > 1 {
            BoxStamp(caption: "ニアミス", value: "×\(outcome.nearMissMultiplierText)")
                .fixedSize()
        }
    }

    @ViewBuilder private var gapText: some View {
        let gap = Formatters.percent(abs(outcome.gapToLine))
        if outcome.isSuccessful {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("あと")
                    .scaledFont(.mincho(metrics.gapWordSize, .extraBold))
                Text(verbatim: "\(gap)%")
                    .font(Theme.display(metrics.gapNumberSize))
                    .foregroundStyle(Theme.red)
                Text(verbatim: "！")
                    .scaledFont(.mincho(metrics.gapWordSize, .extraBold))
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "\(gap)%")
                    .font(Theme.display(metrics.gapNumberSize))
                    .foregroundStyle(Theme.red)
                Text("越えた")
                    .scaledFont(.mincho(metrics.gapWordSize, .extraBold))
            }
        }
    }
}

/// 会長のシルクハットと吹き出し。吹き出しのしっぽはシルクハットのほうを向く
struct ResultChairmanBubble: View {
    let outcome: RoundOutcome
    /// 回収ラインを明かすか。デイリーは、その日のうちは明かさない
    let revealsLine: Bool
    let metrics: ResultMetrics

    private var line: LocalizedStringKey {
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ChairmanHat(leaning: false, size: metrics.hatSize)
                .padding(.top, metrics.tipTop + 7 - metrics.hatSize.height / 2)
            Text(line)
                .scaledFont(.mincho(metrics.bubbleTextSize, metrics.bubbleWeight))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, metrics.bubbleHorizontalPadding)
                .padding(.vertical, metrics.bubbleVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background { InkSurface() }
                .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1.5) }
                .overlay(alignment: .topLeading) {
                    BubbleTip()
                        .offset(x: -BubbleTip.side / 2, y: metrics.tipTop)
                }
                .background {
                    Rectangle().fill(Theme.navy).offset(x: metrics.bubbleShadow, y: metrics.bubbleShadow)
                }
        }
    }
}

extension RoundOutcome {
    /// ニアミス倍率の表示（「×3」の「3」。整数でないときは小数 1 桁）
    var nearMissMultiplierText: String {
        nearMissMultiplier == nearMissMultiplier.rounded()
            ? String(Int(nearMissMultiplier))
            : nearMissMultiplier.formatted(.number.precision(.fractionLength(1)))
    }
}

/// iPhone と Mac で大きさを変える部品の寸法
struct ResultMetrics {
    let cardHorizontalPadding: CGFloat
    let cardVerticalPadding: CGFloat
    let cardSpacing: CGFloat
    let cardInset: CGFloat
    let gaugeBarHeight: CGFloat
    let gaugeLineOverhang: CGFloat
    let gaugeMarkerSize: CGFloat
    let gaugePadding: CGFloat
    let gapWordSize: CGFloat
    let gapNumberSize: CGFloat
    let hatSize: CGSize
    let bubbleTextSize: CGFloat
    let bubbleWeight: Theme.MinchoWeight
    let bubbleHorizontalPadding: CGFloat
    let bubbleVerticalPadding: CGFloat
    let bubbleShadow: CGFloat
    let tipTop: CGFloat

    /// Reveal.png（390 × 844）
    static let compact = Self(
        cardHorizontalPadding: 26,
        cardVerticalPadding: 22,
        cardSpacing: 12,
        cardInset: 8,
        gaugeBarHeight: 42,
        gaugeLineOverhang: 7,
        gaugeMarkerSize: 13,
        gaugePadding: 26,
        gapWordSize: 15,
        gapNumberSize: 40,
        hatSize: CGSize(width: 54, height: 36),
        bubbleTextSize: 16,
        bubbleWeight: .bold,
        bubbleHorizontalPadding: 18,
        bubbleVerticalPadding: 12,
        bubbleShadow: 4,
        tipTop: 14
    )

    /// MacReveal.png（1200 × 760）
    static let wide = Self(
        cardHorizontalPadding: 28,
        cardVerticalPadding: 26,
        cardSpacing: 16,
        cardInset: 6,
        gaugeBarHeight: 34,
        gaugeLineOverhang: 10,
        gaugeMarkerSize: 14,
        gaugePadding: 34,
        gapWordSize: 18,
        gapNumberSize: 52,
        hatSize: CGSize(width: 52, height: 36),
        bubbleTextSize: 17,
        bubbleWeight: .extraBold,
        bubbleHorizontalPadding: 14,
        bubbleVerticalPadding: 10,
        bubbleShadow: 3,
        tipTop: 16
    )
}

/// 吹き出しの左のしっぽ。正方形を 45° 回し、左を向く 2 辺だけに線を引いて、吹き出しの左の線に重ねる
struct BubbleTip: View {
    /// 回す前の正方形の 1 辺
    static let side: CGFloat = 14

    var body: some View {
        // 吹き出しと同じ紙の面にする（平らな色では、吹き出しの紙の地より明るく見える）
        InkSurface()
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.navy).frame(width: 1.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.navy).frame(height: 1.5)
            }
            .frame(width: Self.side, height: Self.side)
            .rotationEffect(.degrees(45))
            .accessibilityHidden(true)
    }
}

/// 結果のゲージ。離した位置（▼）と回収ライン（▲）を並べ、その間（届かなかった分・越えた分）に細い縦線の網をかける
struct RevealGauge: View {
    let released: Double
    /// 回収ライン。nil なら描かない（デイリーのその日のうち）
    let line: Double?
    var barHeight: CGFloat = 42
    /// 回収ラインの線が、ゲージの上下にはみ出す長さ
    var lineOverhang: CGFloat = 7
    /// 「離した ○%」「回収ライン ○%」の文字の大きさ
    var markerSize: CGFloat = 13

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
            .frame(height: barHeight)
            .overlay(alignment: .leading) {
                if let line {
                    // 離した位置と回収ラインの間（届かなかった分・越えた分）
                    let lower = min(max(min(released, line), 0), 1)
                    let upper = min(max(max(released, line), 0), 1)
                    GapHatch()
                        .frame(width: width * (upper - lower), height: barHeight + 2)
                        .offset(x: width * lower)
                }
            }
            .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1.5) }
            .overlay(alignment: .leading) {
                if let line {
                    Rectangle()
                        .fill(Theme.navy)
                        .frame(width: 3, height: barHeight + lineOverhang * 2)
                        .offset(x: width * line - 1.5)
                }
            }
            .overlay {
                marker(text: "離した \(Formatters.percent(released))%", symbol: "▼", color: Theme.navy, above: true)
                    .position(x: width * min(released, 1), y: -(markerSize + 5))
            }
            .overlay {
                if let line {
                    marker(text: "回収ライン \(Formatters.percent(line))%", symbol: "▲", color: Theme.red, above: false)
                        .position(x: width * line, y: barHeight + markerSize + 5)
                }
            }
        }
        .frame(height: barHeight)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private func marker(text: LocalizedStringKey, symbol: String, color: Color, above: Bool) -> some View {
        VStack(spacing: 2) {
            if above {
                Text(text).scaledFont(.mincho(markerSize, .extraBold))
                Text(verbatim: symbol).font(.system(size: 12))
            } else {
                Text(verbatim: symbol).font(.system(size: 12))
                Text(text).scaledFont(.mincho(markerSize, .extraBold))
            }
        }
        .foregroundStyle(color)
        .fixedSize()
    }
}

/// 離した位置と回収ラインの間にかける、紺の縦の細い線（デザインの 1px の線を 3px おき、濃さ 0.6）
private struct GapHatch: View {
    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(Theme.navy))
                x += 3
            }
        }
        .opacity(0.6)
        .accessibilityHidden(true)
    }
}

import SwiftUI

/// iPhone（と、狭い iPad）のラウンド画面。docs/design/Round.png（390 × 844）に合わせる
struct CompactRoundLayout: View {
    let engine: RoundEngine
    let bench: BenchRunner
    /// 画面の高さ。iPhone SE のように低い画面では、数字とボタンを小さくする
    let height: CGFloat

    private var isShort: Bool {
        height < 760
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isShort ? 10 : 14) {
            header
            Ornament()
            ChairmanPanel(
                line: ChairmanLines.line(for: engine),
                stage: ChairmanLines.displayedStage(engine),
                leaning: ChairmanLines.isLeaning(engine)
            )
            DonationReadout(engine: engine, numberSize: isShort ? 46 : 58, unitSize: isShort ? 16 : 20)
            ZStack(alignment: .topTrailing) {
                Group {
                    if case let .unavailable(reason) = engine.phase {
                        UnavailableNotice(reason: reason)
                    } else {
                        HoldButton(engine: engine, diameter: isShort ? 150 : 200)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                Airship(stage: engine.hintStage)
                    .padding(.top, 2)
            }
            PriceFooter(engine: engine, compact: isShort)
        }
        .padding(.horizontal, 20)
        .padding(.top, isShort ? 8 : 16)
        .padding(.bottom, isShort ? 8 : 24)
        .foregroundStyle(Theme.navy)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("速達便")
                    .font(Theme.typewriter(12))
                    .tracking(1)
                    .foregroundStyle(Theme.subText)
                Text("取引先: \(engine.client.name)")
                    .font(Theme.mincho(15))
            }
            Spacer()
            BenchButton(bench: bench)
        }
    }
}

/// 献上量の数字・ゲージ・回収ラインと枠。献上中は毎フレーム読み直す
struct DonationReadout: View {
    let engine: RoundEngine
    var numberSize: CGFloat = 58
    var unitSize: CGFloat = 20
    var gaugeHeight: CGFloat = 22
    var footnoteSize: CGFloat = 12
    var budgetNote: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("献上中（実測）")
                .font(Theme.typewriter(footnoteSize - 1))
                .foregroundStyle(Theme.red)
            TimelineView(.animation(paused: engine.phase != .donating)) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: Formatters.megabytes(engine.donatedBytes))
                            .font(Theme.display(numberSize))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(verbatim: "MB")
                            .font(Theme.display(unitSize))
                    }
                    DonationGauge(fill: engine.donatedFill, safetyLine: SafetyLine.budgetRatio, height: gaugeHeight)
                }
            }
            HStack(spacing: 12) {
                Text("回収ライン: ？？？")
                Text("枠 \(Formatters.megabytes(engine.budgetBytes)) MB")
                if let budgetNote {
                    Text(budgetNote)
                }
            }
            .font(Theme.mincho(footnoteSize, bold: false))
            .foregroundStyle(Theme.subText)
            .padding(.top, 14)
        }
    }
}

/// 「Mac で増設すると ○○ 相当」
struct PriceFooter: View {
    let engine: RoundEngine
    var compact = false
    private let price = MacUpgradePrice.current

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TimelineView(.animation(minimumInterval: 0.1, paused: engine.phase != .donating)) { _ in
                HStack(alignment: .firstTextBaseline) {
                    Text("Mac で増設すると")
                        .font(Theme.mincho(12))
                    Spacer()
                    Text(verbatim: price.formatted(price.amount(for: engine.donatedBytes)))
                        .font(Theme.display(17))
                    Text("相当")
                        .font(Theme.mincho(12))
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .overlay(alignment: .top) { DashedRule() }
            .overlay(alignment: .bottom) { DashedRule() }
            if !compact {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("公式ストアの増設価格 1GB \(price.formattedPricePerGigabyte)\(price.note)")
                        .foregroundStyle(Theme.subText)
                    Text(verbatim: price.changeNote)
                        .foregroundStyle(Theme.red)
                }
                .font(Theme.mincho(11, bold: false))
            }
        }
    }
}

/// 破線の横罫
struct DashedRule: View {
    var body: some View {
        Line()
            .stroke(Theme.navy, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .frame(height: 1.5)
    }
}

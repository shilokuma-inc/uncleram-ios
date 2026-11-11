import SwiftUI

/// Mac（と、広い iPad）の横長のラウンド画面。docs/design/MacRound.png（1200 × 760）に合わせる。
/// 左にポスターと会長、中央に献上量と長押しボタン、右に回収飛行船と献上中の明細。広げると中央の列が伸びる
struct WideRoundLayout: View {
    let engine: RoundEngine
    let bench: BenchRunner

    var body: some View {
        VStack(spacing: 14) {
            header
            Ornament()
            HStack(alignment: .top, spacing: 32) {
                leftColumn.frame(width: 280)
                centerColumn.frame(maxWidth: .infinity)
                rightColumn.frame(width: 300)
            }
            .frame(maxHeight: .infinity)
            footer
        }
        .padding(.horizontal, 36)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .foregroundStyle(Theme.navy)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 14) {
                Image(.hatHalftone)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 29)
                    .accessibilityHidden(true)
                Text(verbatim: "ALLOCATE CORP.")
                    .font(Theme.typewriter(14))
                    .tracking(1.1)
                Text("全人類の RAM を、ひとつの AI に。")
                    .font(Theme.mincho(14))
                    .tracking(0.5)
                    .foregroundStyle(Theme.red)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 28) {
                Text("速達便")
                    .font(Theme.typewriter(12))
                    .tracking(1)
                    .foregroundStyle(Theme.subText)
                Text("取引先: \(engine.client.name)")
                    .font(Theme.mincho(15))
                BenchButton(bench: bench)
            }
        }
    }

    private var leftColumn: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                Image(.handHalftone)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .clipped()
                    .allowsHitTesting(false)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.navy).frame(height: 1.5)
                    }
                    .accessibilityHidden(true)
                Text(verbatim: "I WANT")
                    .font(Theme.display(34))
                    .padding(.top, 8)
                Text(verbatim: "YOUR RAM")
                    .font(Theme.display(34))
                    .foregroundStyle(Theme.red)
                Text("あなたの RAM が必要だ")
                    .font(Theme.mincho(12))
                    .tracking(1.4)
                    .foregroundStyle(Theme.subText)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background { InkSurface() }
            .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 3) }
            .padding(7)
            .overlay { Rectangle().strokeBorder(Theme.red, lineWidth: 3) }
            ChairmanPanel(
                line: ChairmanLines.line(for: engine),
                stage: ChairmanLines.displayedStage(engine),
                leaning: ChairmanLines.isLeaning(engine),
                showsIndicator: false
            )
        }
    }

    private var centerColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            DonationReadout(
                engine: engine,
                numberSize: 88,
                unitSize: 26,
                gaugeHeight: 26,
                footnoteSize: 13,
                budgetNote: budgetNote
            )
            VStack(spacing: 18) {
                if case let .unavailable(reason) = engine.phase {
                    UnavailableNotice(reason: reason)
                } else {
                    HoldButton(engine: engine, diameter: 236, title: holdTitle)
                }
                #if os(macOS)
                HStack(spacing: 10) {
                    Text(verbatim: "space")
                        .font(Theme.typewriter(12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1.5) }
                    Text("クリックの長押しでも献上できます")
                        .font(Theme.mincho(13, bold: false))
                        .foregroundStyle(Theme.subText)
                }
                #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var rightColumn: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Airship(stage: engine.hintStage, baseSize: CGSize(width: 200, height: 150), showsLabel: false)
                    .frame(height: 210)
                HintIndicator(stage: ChairmanLines.displayedStage(engine), fontSize: 13)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .doubleFrame()
            DonationStatement(engine: engine)
        }
    }

    private var footer: some View {
        HStack {
            Text("回収ラインが近づくと、会長の言葉・飛行船・画面のノイズが変わります")
            Spacer()
            #if os(macOS)
            Text("space 長押し: 献上")
                .font(Theme.typewriter(12))
            #endif
        }
        .font(Theme.mincho(12, bold: false))
        .foregroundStyle(Theme.subText)
        .padding(.top, 8)
        .overlay(alignment: .top) { DashedRule() }
    }

    #if os(macOS)
    private var holdTitle: LocalizedStringKey { "スペースを長押し" }
    private var budgetNote: LocalizedStringKey? {
        HostMemoryProbe.isCapped(budget: engine.budgetBytes) ? "（搭載メモリの 50% か 32GB の上限）" : "（使用可能メモリの 60%）"
    }
    #else
    private var holdTitle: LocalizedStringKey { "長押しで献上" }
    private var budgetNote: LocalizedStringKey? { nil }
    #endif
}

/// 献上中の明細（端末・献上量・枠に対して・増設の換算・買取額）
struct DonationStatement: View {
    let engine: RoundEngine
    private let price = MacUpgradePrice.current

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: engine.phase != .donating)) { _ in
            VStack(alignment: .leading, spacing: 11) {
                Text("献上中の明細")
                    .font(Theme.mincho(12))
                    .tracking(3.6)
                    .foregroundStyle(Theme.red)
                row("端末", DeviceDescription.current)
                row("献上量", "\(Formatters.megabytes(engine.donatedBytes)) MB", typewriter: true)
                row("枠に対して", "\(Formatters.percent(engine.donatedFill))%", typewriter: true)
                DashedRule()
                HStack(alignment: .firstTextBaseline) {
                    Text("Mac で増設すると")
                        .font(Theme.mincho(14))
                    Spacer()
                    Text(verbatim: price.formatted(price.amount(for: engine.donatedBytes)))
                        .font(Theme.display(22))
                    Text("相当")
                        .font(Theme.mincho(12))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("\(engine.client.name)の買取額")
                        .font(Theme.mincho(14))
                    Spacer()
                    Text(verbatim: price.formatted(0))
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.red)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("公式ストアの増設価格 1GB \(price.formattedPricePerGigabyte)")
                    HStack(spacing: 6) {
                        Text(verbatim: price.note)
                        Text(verbatim: price.changeNote)
                            .foregroundStyle(Theme.red)
                    }
                }
                .font(Theme.mincho(11, bold: false))
                .foregroundStyle(Theme.subText)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .doubleFrame()
    }

    private func row(_ title: LocalizedStringKey, _ value: String, typewriter: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(verbatim: value)
                .font(typewriter ? Theme.typewriter(14) : Theme.mincho(14, bold: false))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .font(Theme.mincho(14, bold: false))
    }
}

/// 明細に出す端末の種類と搭載メモリ（機種名は送らないが、画面には種類とメモリを出す）
enum DeviceDescription {
    static var current: String {
        let gigabytes = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
        #if os(macOS)
        let kind = "Mac"
        #else
        let kind = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
        return "\(kind)（\(gigabytes)GB）"
    }
}

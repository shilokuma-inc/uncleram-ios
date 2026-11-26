import SwiftUI

/// Mac（と、広い iPad）の横長のラウンド画面。docs/design/MacRound.png（1200 × 760）に合わせる。
/// 左にポスターと会長、中央に献上量と長押しボタン、右に回収飛行船と献上中の明細。広げると中央の列が伸びる
struct WideRoundLayout: View {
    let engine: RoundEngine
    @Environment(\.roundMode) private var roundMode
    let bench: BenchRunner
    /// 「?」で遊び方の 3 コマを開く
    let onShowHowToPlay: () -> Void
    @Environment(LocalStore.self) private var store: LocalStore?

    /// 設定「タップで献上」
    private var tapToDonate: Bool {
        store?.tapToDonate ?? false
    }

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
            CorporateMasthead()
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 28) {
                Text(roundMode.title(practice: engine.isShowingPracticeRound))
                    .scaledFont(.typewriter(12))
                    .tracking(1)
                    .foregroundStyle(Theme.subText)
                Text("取引先: \(engine.client.name)")
                    .scaledFont(.mincho(15))
                BenchButton(bench: bench)
                // 献上中は開かない（長押しを邪魔しないように）
                HowToPlayButton(action: onShowHowToPlay)
                    .disabled(engine.phase == .donating)
            }
        }
    }

    private var leftColumn: some View {
        VStack(spacing: 16) {
            // 文字を大きくすると（Dynamic Type）会長の欄が伸びるので、その分だけ絵を低くして 1 画面に収める
            RecruitPoster(imageHeight: 160...300)
            ChairmanPanel(
                line: ChairmanLines.line(for: engine),
                stage: ChairmanLines.displayedStage(engine),
                leaning: ChairmanLines.isLeaning(engine),
                showsIndicator: false
            )
            .tutorialBubble([.sign, .bluff], edge: .top)
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
            .tutorialBubble([.warning], edge: .top, alignment: .trailing)
            VStack(spacing: 18) {
                if case let .unavailable(reason) = engine.phase {
                    UnavailableNotice(reason: reason)
                } else {
                    HoldButton(engine: engine, diameter: 236)
                        .tutorialBubble([.releaseToDeliver], edge: .top, alignment: .center)
                }
                #if os(macOS)
                HStack(spacing: 10) {
                    Text(verbatim: "space")
                        .scaledFont(.typewriter(12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1.5) }
                    Text(tapToDonate ? "クリックでも献上できます" : "クリックの長押しでも献上できます")
                        .scaledFont(.mincho(13, .medium))
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
                // 文字を大きくすると明細が伸びるので、その分だけ飛行船の欄を低くする。
                // 飛行船は、警告（3 段階目）で大きくなっても欄に収まる大きさにする（練習ラウンドでは、さらに大きく出す）
                GeometryReader { proxy in
                    let emphasized = engine.plan?.isPractice == true
                    let height = min(150, proxy.size.height / (emphasized ? 1.5 : 1.3))
                    Airship(
                        stage: engine.hintStage,
                        baseSize: CGSize(width: height * 4 / 3, height: height),
                        showsLabel: false,
                        emphasized: emphasized
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minHeight: 90, maxHeight: 210)
                .tutorialBubble([.approach], edge: .bottom, alignment: .center)
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
            Text(tapToDonate ? "space: 献上 / 納品" : "space 長押し: 献上")
                .scaledFont(.typewriter(12))
            #endif
        }
        .scaledFont(.mincho(12, .medium))
        .foregroundStyle(Theme.subText)
        .padding(.top, 8)
        .overlay(alignment: .top) { DashedRule() }
    }

    #if os(macOS)
    private var budgetNote: LocalizedStringKey? {
        HostMemoryProbe.isCapped(budget: engine.budgetBytes) ? "（搭載メモリの 50% か 32GB の上限）" : "（使用可能メモリの 60%）"
    }
    #else
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
                    .scaledFont(.mincho(12))
                    .tracking(3.6)
                    .foregroundStyle(Theme.red)
                row("端末", DeviceDescription.current)
                row("献上量", "\(Formatters.megabytes(engine.donatedBytes)) MB", typewriter: true)
                row("枠に対して", "\(Formatters.percent(engine.donatedFill))%", typewriter: true)
                DashedRule()
                HStack(alignment: .firstTextBaseline) {
                    Text("Mac で増設すると")
                        .scaledFont(.mincho(14))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Text(verbatim: price.formatted(price.amount(for: engine.donatedBytes)))
                        .font(Theme.display(22))
                    Text("相当")
                        .scaledFont(.mincho(12))
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("\(engine.client.name)の買取額")
                        .scaledFont(.mincho(14))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Text(verbatim: price.formatted(0))
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.red)
                }
                // 換算額の根拠（単価・時点・税の扱い）は、文字を大きくしても切らずに出す（docs/SPEC.md「金額の表示」の 1.1.6）
                VStack(alignment: .leading, spacing: 2) {
                    Text("公式ストアの増設価格 1GB \(price.formattedPricePerGigabyte)")
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            priceNote
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            priceNote
                        }
                    }
                }
                .scaledFont(.mincho(11, .medium))
                .foregroundStyle(Theme.subText)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .doubleFrame()
    }

    @ViewBuilder private var priceNote: some View {
        Text(verbatim: price.note)
        Text(verbatim: price.changeNote)
            .foregroundStyle(Theme.red)
    }

    private func row(_ title: LocalizedStringKey, _ value: String, typewriter: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(verbatim: value)
                .scaledFont(typewriter ? .typewriter(14) : .mincho(14, .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .scaledFont(.mincho(14, .medium))
    }
}

/// 明細に出す端末の種類と搭載メモリ（機種名は送らないが、画面には種類とメモリを出す）
enum DeviceDescription {
    static var current: String {
        "\(kind)（\(installedGigabytes)GB）"
    }

    /// 端末の種類（iPhone・iPad・Mac）
    static var kind: String {
        #if os(macOS)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    /// 搭載メモリ（GB に丸めた値）
    /// ランキングのクラス分けと同じく、正式な容量に切り上げる（`DeviceMemoryProfile`）
    static var installedGigabytes: Int {
        DeviceMemoryProfile.current.nominalGigabytes
    }
}

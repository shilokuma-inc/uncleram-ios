import MediaAccessibility
import SwiftUI

/// 回収演出（全メモリ 回収完了）。iPhone は docs/design/Collect.png（390 × 844）、Mac と広い iPad は MacCollect.png（1200 × 760）に合わせる。
///
/// 速達便で回収されたら、結果（ResultView）の前に出す。RoundEngine は全メモリを解放してから結果の段階に入るので、
/// この画面が出るときには、メモリはもう解放してある（docs/SPEC.md「メモリの安全」の「演出の前に解放」）。
/// 演出はゲームの世界の中の出来事として、紙と網点の絵だけで見せる。OS の画面（アラート・ホーム画面・クラッシュ画面・
/// ステータスバー）には似せない（審査 1.1.6）
struct CollectEffect: View {
    let outcome: RoundOutcome
    let wide: Bool
    /// 「結果を見る」
    let onShowResult: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 設定「回収演出を控えめにする」
    @Environment(LocalStore.self) private var store: LocalStore?
    @State private var startDate = Date()
    @State private var isFinished = false
    /// 「点滅する光を弱める」。演出は 2 秒ほどで終わるので、出したときの値で決める
    @State private var dimsFlashingLights = MADimFlashingLightsEnabled()

    private var timeline: CollectEffectTimeline {
        CollectEffectTimeline(
            style: .current(
                reduceMotion: reduceMotion,
                reducesCollectEffect: store?.reducesCollectEffect ?? false,
                dimsFlashingLights: dimsFlashingLights
            )
        )
    }

    var body: some View {
        let timeline = timeline
        TimelineView(.animation(paused: isFinished)) { context in
            let frame = isFinished ? timeline.finalFrame : timeline.frame(at: context.date.timeIntervalSince(startDate))
            Group {
                if wide {
                    WideCollectLayout(outcome: outcome, frame: frame, onShowResult: onShowResult)
                } else {
                    CompactCollectLayout(outcome: outcome, frame: frame, onShowResult: onShowResult)
                }
            }
            .offset(x: frame.shake)
        }
        .foregroundStyle(Theme.navy)
        .task {
            try? await Task.sleep(for: .seconds(timeline.duration))
            isFinished = true
        }
    }
}

/// iPhone（と、狭い iPad）の回収演出。低い画面や、文字を大きくしたとき（Dynamic Type）は縦に送れるようにする
private struct CompactCollectLayout: View {
    let outcome: RoundOutcome
    let frame: CollectEffectTimeline.Frame
    let onShowResult: () -> Void

    /// デザインの飛行船の場所の高さ（上の帯と大見出しの間）
    private static let airshipRoomHeight: ClosedRange<CGFloat> = 120...244

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: 480)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            CollectBand(fontSize: 12)
                .zIndex(1)
            // 飛行船の場所。収まらないとき（低い画面・大きい文字）は、ここから縮める。飛行船の絵も、場所に合わせて小さくする
            Color.clear
                .frame(minHeight: Self.airshipRoomHeight.lowerBound, maxHeight: Self.airshipRoomHeight.upperBound)
                .layoutPriority(1)
                .overlay(alignment: .topLeading) {
                    GeometryReader { room in
                        airship(room: room.size)
                    }
                }
            CollectHeading(outcome: outcome, frame: frame, headlineSize: 50, stampDiameter: 80)
            CollectStatement(outcome: outcome, textSize: 15, rowSize: 14, lineSize: 12)
                .opacity(frame.detailsOpacity)
            Spacer(minLength: 0)
            CollectActions(frame: frame, noteSize: 13, buttonFontSize: 17, buttonPadding: 15, onShowResult: onShowResult)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }

    /// デザインでは、飛行船（470 × 324）は列の左に 36pt はみ出し、上は帯より 30pt 上から、下は大見出しに 34pt かかる
    private func airship(room: CGSize) -> some View {
        let columnWidth = room.width + 40
        let height = min(room.height + 80, 324 * columnWidth / 390)
        let width = height * 470 / 324
        return GlitchedAirship(opacity: frame.airshipOpacity, glitch: frame.glitch)
            .frame(width: width, height: height)
            .offset(
                x: -20 - width * 36 / 470 + frame.airshipOffset.width * width,
                y: -30 * height / 324 + frame.airshipOffset.height * height
            )
    }
}

/// Mac（と、広い iPad）の回収演出。左を飛行船が覆い、右の列に大見出し・明細・「結果を見る」を置く
private struct WideCollectLayout: View {
    let outcome: RoundOutcome
    let frame: CollectEffectTimeline.Frame
    let onShowResult: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 1200, proxy.size.height / 760)
            VStack(alignment: .leading, spacing: 14) {
                CollectBand(fontSize: 13)
                HStack(spacing: 40) {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 20) {
                        CollectHeading(outcome: outcome, frame: frame, headlineSize: 62, stampDiameter: 96)
                        CollectStatement(outcome: outcome, textSize: 16, rowSize: 15, lineSize: 13)
                            .opacity(frame.detailsOpacity)
                        CollectActions(frame: frame, noteSize: 13, buttonFontSize: 18, buttonPadding: 16, onShowResult: onShowResult)
                    }
                    .frame(width: 400)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 36)
            .padding(.top, 26)
            .padding(.bottom, 20)
            .background(alignment: .topLeading) {
                // デザインでは、飛行船（860 × 593）は左に 40pt はみ出し、上から 70pt のところに置く
                GlitchedAirship(opacity: frame.airshipOpacity, glitch: frame.glitch)
                    .frame(width: 860 * scale, height: 593 * scale)
                    .offset(
                        x: (-40 + 860 * frame.airshipOffset.width) * scale,
                        y: (70 + 593 * frame.airshipOffset.height) * scale
                    )
            }
        }
    }
}

/// 上の帯「ALLOCATE CORP. 回収部 · 速達便」
private struct CollectBand: View {
    let fontSize: CGFloat

    var body: some View {
        Text("ALLOCATE CORP. 回収部 · 速達便")
            .scaledFont(.typewriter(fontSize))
            .tracking(fontSize * 0.06)
            .foregroundStyle(Theme.lightPaper)
            .padding(.horizontal, fontSize * 0.7)
            .padding(.vertical, fontSize * 0.35)
            .background { InkSurface(color: Theme.navy) }
    }
}

/// 大見出しと判子。判子は、抜き打ち回収（早期回収）のときは結果と同じ「抜き打ち回収」にする
private struct CollectHeading: View {
    let outcome: RoundOutcome
    let frame: CollectEffectTimeline.Frame
    let headlineSize: CGFloat
    let stampDiameter: CGFloat

    private var stamp: LocalizedStringKey {
        outcome.plan.isEarlyCollection ? "抜き打ち\n回収" : "回収済"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CollectHeadline(size: headlineSize, colorShift: frame.colorShift)
                .opacity(frame.headlineOpacity)
                .frame(maxWidth: .infinity, alignment: .leading)
            CircleStamp(text: stamp, diameter: stampDiameter, angle: .degrees(-14))
                .scaleEffect(frame.stampScale)
                .opacity(frame.stampOpacity)
                .padding(.top, 6)
                .padding(.trailing, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(stamp))
        }
    }
}

/// 大見出し「全メモリ 回収完了」（Dela Gothic One）。赤と青の版ずれを後ろに重ねる。Dynamic Type では大きさを変えない
struct CollectHeadline: View {
    let size: CGFloat
    /// 赤と青のずれ。デザインのずれ（±3pt）に対する倍率
    var colorShift: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            lines
                .foregroundStyle(Theme.blue.opacity(0.75))
                .offset(x: 3 * colorShift)
            lines
                .foregroundStyle(Theme.red.opacity(0.85))
                .offset(x: -3 * colorShift)
            lines
        }
        .font(Theme.heading(size))
        .tracking(size * 0.01)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("全メモリ回収完了"))
        .accessibilityAddTraits(.isHeader)
    }

    /// 行の高さは、デザインと同じく文字の 1.12 倍に詰める（書体のままだと 1.45 倍になる）
    private var lines: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("全メモリ")
                .frame(height: size * 1.12)
            Text("回収完了")
                .frame(height: size * 1.12)
        }
    }
}

/// 会長の一言と、このラウンドの献上分（○○ MB → 0 MB）、回収ラインと超過分
private struct CollectStatement: View {
    let outcome: RoundOutcome
    let textSize: CGFloat
    let rowSize: CGFloat
    let lineSize: CGFloat

    var body: some View {
        let figures = CollectFigures(outcome: outcome)
        VStack(alignment: .leading, spacing: textSize * 0.67) {
            Text("個人の端末にメモリを置いておくのは、資源の無駄遣いです。ご提供分は当社の AI が責任をもって有効活用いたします。")
                .scaledFont(.mincho(textSize))
                .lineSpacing(textSize * 0.33)
                .fixedSize(horizontal: false, vertical: true)
            // 1 行に入らないとき（文字を大きくしたときなど）は、量を 2 行目に送る
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    donationLabel
                    Spacer(minLength: 12)
                    amounts(figures)
                }
                VStack(alignment: .leading, spacing: 4) {
                    donationLabel
                    amounts(figures)
                }
            }
            .scaledFont(.typewriter(rowSize))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("このラウンドの献上分は \(figures.donatedText) MB から 0 MB に"))
            Text("回収ラインは \(figures.lineText) MB でした（\(figures.excessText) MB 超過）")
                .scaledFont(.mincho(lineSize, .medium))
                .foregroundStyle(Theme.subText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .doubleFrame()
    }

    private var donationLabel: some View {
        Text("このラウンドの献上分")
            .foregroundStyle(Theme.red)
    }

    private func amounts(_ figures: CollectFigures) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "\(figures.donatedText) MB")
                .strikethrough()
            Text(verbatim: "→ 0 MB")
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// 「端末のメモリはすでに解放済みです」と「結果を見る」。出かかるまでは押せないようにする（長押しの指を離しただけで進まないように）
private struct CollectActions: View {
    let frame: CollectEffectTimeline.Frame
    let noteSize: CGFloat
    let buttonFontSize: CGFloat
    let buttonPadding: CGFloat
    let onShowResult: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("端末のメモリはすでに解放済みです")
                .scaledFont(.mincho(noteSize, .medium))
                .foregroundStyle(Theme.subText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            PrimaryInkButton(
                title: "結果を見る",
                fontSize: buttonFontSize,
                verticalPadding: buttonPadding,
                color: Theme.navy,
                action: onShowResult
            )
            .keyboardShortcut(frame.isActionEnabled ? KeyboardShortcut.defaultAction : nil)
            .allowsHitTesting(frame.isActionEnabled)
            .accessibilityHidden(!frame.isActionEnabled)
        }
        .opacity(frame.actionsOpacity)
    }
}

/// 回収飛行船の網点の絵（1910 年の写真）と、横にずれた帯（グリッチ）。
/// ずれた帯は、中を紙で覆ってから、横にずらした絵を描く。赤と青の帯は、デザインと同じく乗算で重ねる
struct GlitchedAirship: View {
    var opacity: Double = 1
    var glitch: CollectEffectTimeline.Glitch?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                image
                    .opacity(opacity)
                if let glitch {
                    let pattern = GlitchPattern.pattern(for: glitch)
                    ForEach(pattern.slices.indices, id: \.self) { index in
                        let slice = pattern.slices[index]
                        ZStack(alignment: .topLeading) {
                            Theme.paper
                            image
                                .offset(x: slice.shift * proxy.size.width)
                        }
                        .clipShape(BandShape(top: slice.top, height: slice.height))
                    }
                    BandShape(top: pattern.red.top, height: pattern.red.height)
                        .fill(Theme.red.opacity(0.5))
                        .blendMode(.multiply)
                    BandShape(top: pattern.blue.top, height: pattern.blue.height)
                        .fill(Theme.blue.opacity(0.55))
                        .blendMode(.multiply)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 絵の縦横比（900 × 620）は、置く枠と同じにしてあるので、枠いっぱいに描く
    private var image: some View {
        Image(.airshipHalftone)
            .resizable()
    }
}

/// グリッチの帯の位置（飛行船の絵の高さ・幅に対する割合）
private struct GlitchPattern {
    struct Slice {
        let top: CGFloat
        let height: CGFloat
        /// 横のずれ（右が正）
        let shift: CGFloat
    }

    struct Band {
        let top: CGFloat
        let height: CGFloat
    }

    let slices: [Slice]
    let red: Band
    let blue: Band

    static func pattern(for glitch: CollectEffectTimeline.Glitch) -> Self {
        switch glitch {
        case .first: first
        case .second: second
        case .settled: settled
        }
    }

    private static let first = Self(
        slices: [
            Slice(top: 0.20, height: 0.10, shift: 0.09),
            Slice(top: 0.46, height: 0.06, shift: -0.07),
            Slice(top: 0.74, height: 0.07, shift: 0.05)
        ],
        red: Band(top: 0.46, height: 0.06),
        blue: Band(top: 0.21, height: 0.025)
    )

    private static let second = Self(
        slices: [
            Slice(top: 0.34, height: 0.05, shift: -0.11),
            Slice(top: 0.57, height: 0.09, shift: 0.04),
            Slice(top: 0.82, height: 0.04, shift: -0.06)
        ],
        red: Band(top: 0.82, height: 0.04),
        blue: Band(top: 0.58, height: 0.02)
    )

    /// デザイン（Collect.html の 470 × 324 の飛行船）の形
    private static let settled = Self(
        slices: [
            Slice(top: 0.302, height: 0.080, shift: -0.051),
            Slice(top: 0.543, height: 0.043, shift: 0.064),
            Slice(top: 0.660, height: 0.105, shift: -0.026)
        ],
        red: Band(top: 0.302, height: 0.080),
        blue: Band(top: 0.698, height: 0.022)
    )
}

/// 横いっぱいの帯（上と高さは、枠の高さに対する割合）
nonisolated struct BandShape: Shape {
    let top: CGFloat
    let height: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY + rect.height * top, width: rect.width, height: rect.height * height))
    }
}

/// 回収演出に出す量（MB）。表示は切り捨てた MB にし、超過分は表示する 2 つの値の差にする（画面の上で引き算が合うように）
struct CollectFigures: Equatable {
    let donatedMegabytes: UInt64
    let lineMegabytes: UInt64

    init(outcome: RoundOutcome) {
        donatedMegabytes = outcome.donatedBytes / 1_048_576
        lineMegabytes = UInt64(Double(outcome.budgetBytes) * outcome.plan.collectionLine) / 1_048_576
    }

    var excessMegabytes: UInt64 {
        donatedMegabytes > lineMegabytes ? donatedMegabytes - lineMegabytes : 0
    }

    var donatedText: String {
        Formatters.integer(Int(donatedMegabytes))
    }

    var lineText: String {
        Formatters.integer(Int(lineMegabytes))
    }

    var excessText: String {
        Formatters.integer(Int(excessMegabytes))
    }
}

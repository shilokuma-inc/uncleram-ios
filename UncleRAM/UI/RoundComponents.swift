import SwiftUI

/// 飾り罫（横に繰り返す）
struct Ornament: View {
    var height: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            let image = context.resolve(Image(.borderA))
            let natural = image.size
            guard natural.height > 0 else {
                return
            }
            let width = natural.width * size.height / natural.height
            var x: CGFloat = 0
            while x < size.width {
                context.draw(image, in: CGRect(x: x, y: 0, width: width, height: size.height))
                x += width
            }
        }
        .frame(height: height)
        .opacity(0.85)
        .accessibilityHidden(true)
    }
}

/// ヒントの段階の表示（気配 ■□□ など）
struct HintIndicator: View {
    let stage: RoundPlan.HintStage
    var fontSize: CGFloat = 12

    private var label: LocalizedStringKey {
        switch stage {
        case .none:
            "回収飛行船"
        case .sign:
            "気配"
        case .approach:
            "回収飛行船 接近"
        case .warning:
            "警告"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
            ForEach(1...3, id: \.self) { index in
                ZStack {
                    if index <= stage.rawValue {
                        InkSurface(color: Theme.red)
                    }
                }
                .frame(width: 10, height: 10)
                .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1) }
            }
        }
        .font(Theme.mincho(fontSize, bold: false))
        .foregroundStyle(Theme.subText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(stage.rawValue) / 3"))
    }
}

/// マロック会長のシルクハット。気配が出ると傾いて、赤い「〃」が出る
struct ChairmanHat: View {
    var leaning: Bool
    var size = CGSize(width: 60, height: 40)

    var body: some View {
        Image(.hatHalftone)
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
            .rotationEffect(.degrees(leaning ? -10 : 0), anchor: .bottom)
            .overlay(alignment: .topTrailing) {
                if leaning {
                    Text(verbatim: "〃")
                        .font(Theme.mincho(16))
                        .foregroundStyle(Theme.red)
                        .offset(x: 10, y: -8)
                }
            }
            .animation(.spring(duration: 0.3), value: leaning)
            .accessibilityHidden(true)
    }
}

/// 会長の吹き出しの欄（シルクハット・名前・台詞・ヒントの段階）
struct ChairmanPanel: View {
    let line: LocalizedStringKey
    let stage: RoundPlan.HintStage
    let leaning: Bool
    var showsIndicator = true

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                ChairmanHat(leaning: leaning)
                Text("マロック会長")
                    .font(Theme.typewriter(10))
                    .foregroundStyle(Theme.subText)
            }
            .fixedSize()
            Rectangle()
                .fill(.clear)
                .frame(width: 1.5)
                .overlay {
                    Line(axis: .vertical)
                        .stroke(Theme.navy, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            VStack(alignment: .leading, spacing: 6) {
                Text(line)
                    .font(Theme.mincho(15))
                    .lineSpacing(5)
                    .foregroundStyle(Theme.navy)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsIndicator {
                    HintIndicator(stage: stage)
                }
            }
        }
        // 区切りの破線を、台詞の高さに合わせる（広げると欄が縦に伸びる）
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .doubleFrame()
        .accessibilityElement(children: .combine)
    }
}

/// 直線（破線の区切りに使う）
struct Line: Shape {
    enum Axis {
        case horizontal
        case vertical
    }

    var axis: Axis = .horizontal

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch axis {
        case .horizontal:
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        case .vertical:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        return path
    }
}

/// 献上のゲージ。赤い斜線の帯が献上量、紺の縦線が安全ライン
struct DonationGauge: View {
    let fill: Double
    let safetyLine: Double
    var height: CGFloat = 22
    var showsSafetyLabel = true

    var body: some View {
        GeometryReader { proxy in
            let inner = max(0, proxy.size.width - 4)
            ZStack(alignment: .leading) {
                InkSurface()
                StripedInk()
                    .frame(width: inner * min(max(fill, 0), 1))
                    .padding(2)
            }
            .frame(height: height)
            .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1.5) }
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Theme.navy)
                    .frame(width: 2, height: height + 16)
                    .offset(x: proxy.size.width * safetyLine - 1)
            }
            .overlay {
                if showsSafetyLabel {
                    Text("▲ 安全ライン")
                        .font(Theme.mincho(12))
                        .foregroundStyle(Theme.navy)
                        .fixedSize()
                        .position(x: proxy.size.width * safetyLine, y: height + 12)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(Text("献上量"))
        .accessibilityValue(Text("枠の \(Formatters.percent(fill))%"))
    }
}

/// 赤のインクに、明るい斜線を重ねた帯
struct StripedInk: View {
    var body: some View {
        InkSurface(color: Theme.red)
            .overlay {
                Canvas { context, size in
                    var x: CGFloat = -size.height
                    while x < size.width {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x + size.height, y: 0))
                        context.stroke(path, with: .color(Theme.lightPaper.opacity(0.22)), lineWidth: 2)
                        x += 6
                    }
                }
            }
            .clipped()
    }
}

/// 長押しのボタン（赤い丸に二重の明るい線、外に紺の線）
struct HoldButtonFace: View {
    let holding: Bool
    var diameter: CGFloat = 200
    var title: LocalizedStringKey = "長押しで献上"

    var body: some View {
        ZStack {
            InkSurface(color: Theme.red)
                .clipShape(Circle())
            Circle()
                .strokeBorder(Theme.lightPaper, lineWidth: 1.3)
            Circle()
                .strokeBorder(Theme.lightPaper, lineWidth: 1.3)
                .padding(2.7)
            VStack(spacing: diameter * 0.03) {
                Text(holding ? "HOLDING" : "PRESS & HOLD")
                    .font(Theme.display(diameter * 0.055))
                    .tracking(diameter * 0.011)
                Text(holding ? "献上中" : title)
                    .font(Theme.mincho(diameter * 0.12))
                    .tracking(diameter * 0.01)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, diameter * 0.1)
                Text("離すと納品")
                    .font(Theme.mincho(diameter * 0.06))
                    .tracking(diameter * 0.006)
            }
            .foregroundStyle(Theme.lightPaper)
        }
        .frame(width: diameter, height: diameter)
        .padding(diameter * 0.03)
        .overlay {
            Circle().strokeBorder(Theme.navy, lineWidth: 2)
        }
        .scaleEffect(holding ? 0.97 : 1)
        .animation(.easeOut(duration: 0.12), value: holding)
    }
}

/// 回収飛行船。段階が上がるほど大きく、近くに寄ってくる
struct Airship: View {
    let stage: RoundPlan.HintStage
    var baseSize = CGSize(width: 104, height: 72)
    var showsLabel = true

    private var scale: CGFloat {
        switch stage {
        case .none, .sign:
            1
        case .approach:
            1.15
        case .warning:
            1.3
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Image(.airshipHalftone)
                .resizable()
                .scaledToFit()
                .frame(width: baseSize.width, height: baseSize.height)
                .scaleEffect(scale, anchor: .topTrailing)
                .animation(.easeInOut(duration: 0.6), value: stage)
            if showsLabel {
                Text("回収飛行船")
                    .font(Theme.typewriter(10))
                    .foregroundStyle(Theme.red)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 警告（3 段階目）の画面のノイズ。インクがかすれたような横の帯を走らせる（OS の画面には似せない）。
/// 「視差効果を減らす」が有効なときは、動かさずに紙の汚れのように止めて見せる（docs/SPEC.md「アクセシビリティ」）
struct InkNoise: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let frame = reduceMotion ? 0 : UInt64(timeline.date.timeIntervalSinceReferenceDate * 30)
                var generator = SplitMix64(seed: frame)
                for _ in 0..<14 {
                    let y = generator.uniform(0...Double(size.height))
                    let height = generator.uniform(1...7)
                    let x = generator.uniform(-40...Double(size.width) * 0.6)
                    let width = generator.uniform(40...Double(size.width))
                    let color = generator.chance(0.7) ? Theme.navy : Theme.red
                    context.fill(
                        Path(CGRect(x: x, y: y, width: width, height: height)),
                        with: .color(color.opacity(generator.uniform(0.05...0.18)))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 丸い判子（納品・回収など）
struct CircleStamp: View {
    let text: LocalizedStringKey
    var color: Color = Theme.red
    var diameter: CGFloat = 140

    var body: some View {
        ZStack {
            Circle().strokeBorder(color, lineWidth: 2.5)
            Circle().strokeBorder(color, lineWidth: 1).padding(6)
            Text(text)
                .font(Theme.mincho(diameter * 0.22))
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .padding(diameter * 0.15)
        }
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(-8))
        .opacity(0.9)
    }
}

/// 四角い判子（ニアミス ×3 など）
struct BoxStamp: View {
    let caption: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(caption)
                .font(Theme.mincho(12))
                .tracking(3)
            Text(verbatim: value)
                .font(Theme.display(28))
        }
        .foregroundStyle(Theme.red)
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .overlay { Rectangle().strokeBorder(Theme.red, lineWidth: 2.5) }
        .rotationEffect(.degrees(-4))
    }
}

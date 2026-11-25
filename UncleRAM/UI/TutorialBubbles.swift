import SwiftUI

/// 最初の 1 回で覚えることを、その場面が初めて来たときだけ出す会長の吹き出し（docs/SPEC.md「説明なしで分かる UI」）。
/// 一度に 1 つ、20 字前後。一度見せたものは端末に覚えておき、設定「使い方をもう一度見る」で元に戻す
enum TutorialBubble: String, CaseIterable {
    /// 献上量が枠の 20% に来たとき
    case releaseToDeliver
    /// ヒントの 1 段階目（気配）が初めて出たとき
    case sign
    /// 2 段階目（接近）
    case approach
    /// 3 段階目（警告）
    case warning
    /// はったりの種明かし（会長がにやりと笑うとき）。毎回の「……なんてな。」とは別に、初めてのときだけ出す（CLAUDE.md、2026-11-23）
    case bluff
    /// 早期回収で初めて回収されたとき（結果の「抜き打ち回収」の判子の横）
    case earlyCollection

    /// 献上量がこれを越えたら「離せば納品だ」を出す（枠に対する割合）
    static let releaseHintFill = 0.2

    /// 吹き出しの文言。設定「タップで献上」のときは、離しても納品しないので、もう一度押すことを伝える
    func text(tapToDonate: Bool) -> LocalizedStringKey {
        switch self {
        case .releaseToDeliver: tapToDonate ? "もう一度押せば納品だ" : "離せば納品だ"
        case .sign: "会長の機嫌が変わった"
        case .approach: "飛行船が近い"
        case .warning: "もう危ない"
        case .bluff: "…なんてな"
        case .earlyCollection: "たまに早いこともある"
        }
    }

    /// 吹き出しの下に小さく添える一言（docs/design/Tutorial.png の「＝ 回収ラインが近いかも」）
    var caption: LocalizedStringKey? {
        switch self {
        case .sign: "＝ 回収ラインが近いかも"
        default: nil
        }
    }

    /// VoiceOver で読み上げる文（`text(tapToDonate:)` と同じ文言）
    func announcement(tapToDonate: Bool) -> String {
        switch self {
        case .releaseToDeliver: String(localized: tapToDonate ? "もう一度押せば納品だ" : "離せば納品だ")
        case .sign: String(localized: "会長の機嫌が変わった")
        case .approach: String(localized: "飛行船が近い")
        case .warning: String(localized: "もう危ない")
        case .bluff: String(localized: "…なんてな")
        case .earlyCollection: String(localized: "たまに早いこともある")
        }
    }

    /// ヒントの段階に対応する吹き出し
    static func forHintStage(_ stage: RoundPlan.HintStage) -> TutorialBubble? {
        switch stage {
        case .none: nil
        case .sign: .sign
        case .approach: .approach
        case .warning: .warning
        }
    }
}

/// 吹き出しを出す係。見せたものは `LocalStore` に覚えておき、二度と出さない
@Observable
final class TutorialCoach {
    /// 今出している吹き出し
    private(set) var current: TutorialBubble?
    /// 端末の記録。撮影モードと計測では渡さない（吹き出しを出さず、見たことにもしない）
    @ObservationIgnored var store: LocalStore?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// 吹き出しを出しておく秒数
    static let displayDuration: TimeInterval = 3

    init(store: LocalStore? = nil) {
        self.store = store
    }

    /// まだ見せていなければ出す。新しい吹き出しを出すと、前の吹き出しは消える（一度に 1 つ）
    func reveal(_ bubble: TutorialBubble) {
        guard let store, !store.seenTutorialBubbles.contains(bubble.rawValue) else {
            return
        }
        store.seenTutorialBubbles.insert(bubble.rawValue)
        current = bubble
        AccessibilityNotification.Announcement(bubble.announcement(tapToDonate: store.tapToDonate)).post()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.displayDuration))
            guard !Task.isCancelled, let self, self.current == bubble else {
                return
            }
            self.current = nil
        }
    }

    /// ラウンドが終わったときなど、今の吹き出しを消す
    func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        current = nil
    }
}

/// 会長の吹き出し（docs/design/Tutorial.png）。紙の札に紺の影を付け、指し示す側に三角のしっぽを出す
struct TutorialBubbleView: View {
    let bubble: TutorialBubble
    @Environment(LocalStore.self) private var store: LocalStore?
    /// しっぽを出す辺（吹き出しが部品の下にあるときは上、上にあるときは下）
    var tailEdge: VerticalEdge = .top
    var tailAlignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bubble.text(tapToDonate: store?.tapToDonate ?? false))
                .scaledFont(.mincho(15, .extraBold))
            if let caption = bubble.caption {
                Text(caption)
                    .scaledFont(.mincho(11))
                    .foregroundStyle(Theme.subText)
            }
        }
        .foregroundStyle(Theme.navy)
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background { InkSurface(color: Theme.lightPaper) }
        .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1.5) }
        .overlay(alignment: Alignment(horizontal: tailAlignment, vertical: tailEdge == .top ? .top : .bottom)) {
            tail
        }
        .background {
            Rectangle().fill(Theme.navy).offset(x: 3, y: 3)
        }
        // 読み上げは TutorialCoach が出すときに 1 回だけ行う
        .accessibilityHidden(true)
    }

    /// 紙の色の小さな四角を 45° 回し、外側の 2 辺だけに紺の線を引いたしっぽ（札の枠の上に重ねて、枠の線を隠す）
    private var tail: some View {
        TailShape()
            .fill(Theme.lightPaper)
            .overlay { TailShape(edgesOnly: true).stroke(Theme.navy, lineWidth: 1.5) }
            .frame(width: 14, height: 7)
            .rotationEffect(.degrees(tailEdge == .top ? 0 : 180))
            .offset(y: tailEdge == .top ? -6.5 : 6.5)
            .padding(.horizontal, tailAlignment == .center ? 0 : 22)
    }
}

/// 上向きの三角（しっぽ）。edgesOnly なら、底辺を除く 2 辺だけ
private struct TailShape: Shape {
    var edgesOnly = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        if !edgesOnly {
            path.closeSubpath()
        }
        return path
    }
}

extension View {
    /// bubbles のどれかを出しているときだけ、この部品のすぐ下（edge が .bottom）か上（.top）に吹き出しを出す
    /// （その兆しのすぐ横に一言）。しっぽは部品のほうを向く
    func tutorialBubble(_ bubbles: Set<TutorialBubble>, edge: VerticalEdge, alignment: HorizontalAlignment = .leading) -> some View {
        modifier(TutorialBubbleModifier(bubbles: bubbles, edge: edge, horizontal: alignment))
    }
}

private struct TutorialBubbleModifier: ViewModifier {
    let bubbles: Set<TutorialBubble>
    let edge: VerticalEdge
    let horizontal: HorizontalAlignment
    @Environment(TutorialCoach.self) private var coach: TutorialCoach?

    /// 部品と吹き出しの間（しっぽの分）
    nonisolated private static let gap: CGFloat = 10

    private var shown: TutorialBubble? {
        guard let current = coach?.current, bubbles.contains(current) else {
            return nil
        }
        return current
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: Alignment(horizontal: horizontal, vertical: edge == .bottom ? .bottom : .top)) {
                ZStack {
                    if let shown {
                        TutorialBubbleView(bubble: shown, tailEdge: edge == .bottom ? .top : .bottom, tailAlignment: horizontal)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .allowsHitTesting(false)
                // 吹き出しの上の辺を部品の下の辺に（上に出すときは、下の辺を上の辺に）合わせる。
                // 位置の指定は、出し入れ（transition）の外側に付けないと効かない
                .alignmentGuide(edge == .bottom ? .bottom : .top) { dimension in
                    edge == .bottom ? dimension[.top] - Self.gap : dimension[.bottom] + Self.gap
                }
            }
            .animation(.easeOut(duration: 0.2), value: shown)
            // 吹き出しが隣の部品の下に隠れないよう、出している間は前に出す
            .zIndex(shown == nil ? 0 : 1)
    }
}

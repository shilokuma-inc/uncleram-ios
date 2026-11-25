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

    var text: LocalizedStringKey {
        switch self {
        case .releaseToDeliver: "離せば納品だ"
        case .sign: "会長の機嫌が変わった"
        case .approach: "飛行船が近い"
        case .warning: "もう危ない"
        case .bluff: "…なんてな"
        case .earlyCollection: "たまに早いこともある"
        }
    }

    /// VoiceOver で読み上げる文（`text` と同じ文言）
    var announcement: String {
        switch self {
        case .releaseToDeliver: String(localized: "離せば納品だ")
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
        AccessibilityNotification.Announcement(bubble.announcement).post()
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

/// 会長の吹き出し（紙の札に紺の影）
struct TutorialBubbleView: View {
    let bubble: TutorialBubble

    var body: some View {
        Text(bubble.text)
            .scaledFont(.mincho(14))
            .foregroundStyle(Theme.navy)
            .fixedSize()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background { InkSurface(color: Theme.lightPaper) }
            .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1.5) }
            .background {
                Rectangle().fill(Theme.navy).offset(x: 3, y: 3)
            }
            // 読み上げは TutorialCoach が出すときに 1 回だけ行う
            .accessibilityHidden(true)
    }
}

extension View {
    /// bubbles のどれかを出しているときだけ、この部品の横に吹き出しを重ねる（その兆しのすぐ横に一言）
    func tutorialBubble(_ bubbles: Set<TutorialBubble>, alignment: Alignment, offset: CGSize = .zero) -> some View {
        modifier(TutorialBubbleModifier(bubbles: bubbles, alignment: alignment, offset: offset))
    }
}

private struct TutorialBubbleModifier: ViewModifier {
    let bubbles: Set<TutorialBubble>
    let alignment: Alignment
    let offset: CGSize
    @Environment(TutorialCoach.self) private var coach: TutorialCoach?

    private var shown: TutorialBubble? {
        guard let current = coach?.current, bubbles.contains(current) else {
            return nil
        }
        return current
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if let shown {
                    TutorialBubbleView(bubble: shown)
                        .offset(offset)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.2), value: shown)
            // 吹き出しが隣の部品の下に隠れないよう、出している間は前に出す
            .zIndex(shown == nil ? 0 : 1)
    }
}

import SwiftUI

/// 共有のプレビューの、形（画像・動画・文字）を切り替える帯
struct ShareTabBar<Tab: Hashable>: View {
    @Binding var selection: Tab
    let tabs: [(tab: Tab, title: LocalizedStringKey)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.navy)
                        .frame(width: 1.5)
                }
                button(item.tab, title: item.title)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 3)
        .overlay(alignment: .top) { DoubleRule() }
        .overlay(alignment: .bottom) { DoubleRule() }
    }

    private func button(_ value: Tab, title: LocalizedStringKey) -> some View {
        let selected = selection == value
        return Button {
            selection = value
        } label: {
            Text(title)
                .scaledFont(.mincho(14, selected ? .extraBold : .bold))
                .tracking(1.7)
                .foregroundStyle(selected ? Theme.lightPaper : Theme.navy)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background {
                    if selected {
                        InkSurface(color: Theme.navy)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 明細書のプレビュー。書き出す画像と同じものを縮めて見せる（VoiceOver では明細書の項目を 1 行ずつ読める）
struct CanvasPreview: View {
    let format: ShareImageFormat
    let content: TributeStatementContent
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    var body: some View {
        let size = format.canvasSize
        let scale = max(0.1, min(1, maxWidth / size.width, maxHeight / size.height))
        ShareImageCanvas(format: format, content: content)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
            .overlay { Rectangle().strokeBorder(Theme.navy.opacity(0.4), lineWidth: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("献上明細書のプレビュー"))
    }
}

/// 破線の枠（文面の欄）
struct DashedBorder: View {
    var body: some View {
        Rectangle()
            .strokeBorder(Theme.navy, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
    }
}

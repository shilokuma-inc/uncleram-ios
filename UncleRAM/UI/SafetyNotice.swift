import SwiftUI

/// 初回の案内。最初の起動で 1 回だけ、タイトルの上に重ねて出す（docs/SPEC.md「初回起動と設定」。文言は 2026-11-26 にユーザーが決定）。
/// 明細書と同じ紙の資料の見た目にして、OS のアラートには似せない（審査 1.1.6）
struct SafetyNotice: View {
    let onAcknowledge: () -> Void

    var body: some View {
        ZStack {
            Theme.navy.opacity(0.45)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            ScrollView {
                card
                    .padding(.horizontal, 24)
                    .padding(.vertical, 40)
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center)
        }
        .accessibilityAddTraits(.isModal)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: "ALLOCATE CORP.")
                .scaledFont(.typewriter(11))
                .tracking(1.1)
                .foregroundStyle(Theme.subText)
            Text("ご提供の前に")
                .scaledFont(.mincho(22, .extraBold))
                .tracking(2)
                .accessibilityAddTraits(.isHeader)
            DashedRule()
            VStack(alignment: .leading, spacing: 12) {
                item("このゲームは、端末の本物のメモリを確保して遊びます。")
                item("献上している間、裏で開いているアプリが終了することがあります。")
                item("端末が速くなるアプリではありません。")
            }
            DashedRule()
            PrimaryInkButton(title: "承知しました", fontSize: 17, verticalPadding: 14, action: onAcknowledge)
                .keyboardShortcut(.defaultAction)
            Text("発行　アロケート社")
                .scaledFont(.mincho(11, .medium))
                .foregroundStyle(Theme.subText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(Theme.navy)
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .doubleFrame(inset: 8)
    }

    private func item(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "■")
                .font(Theme.mincho(10))
                .foregroundStyle(Theme.red)
                .accessibilityHidden(true)
            Text(text)
                .scaledFont(.mincho(15))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

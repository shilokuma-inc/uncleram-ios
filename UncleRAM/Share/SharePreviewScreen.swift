import SwiftUI

/// 共有のプレビュー（docs/SPEC.md「共有機能」の「共有の入口」、docs/design/MacResult.png の「明細書をシェア」の列）。
///
/// 画像（4:5 / 9:16）と文字を切り替えて、共有シート（`ShareLink`）から本人が投稿する。自動投稿や、共有と引き換えの報酬は置かない。
/// 「画像を保存」と「文字をコピー」も置き、Mac は画像をクリップボードにもコピーできる。動画は別の PR で足す
struct SharePreviewScreen: View {
    enum Tab {
        case image
        case text
    }

    /// これより広いときは、左に明細書、右に操作を並べる（Mac と広い iPad）
    static let wideLayoutMinimumWidth: CGFloat = 760

    let summary: ShareSummary

    @Environment(\.dismiss) private var dismiss
    /// 「機種名を隠す」を覚えておく先。プレビューなど、AppRoot の外で開いたときは無い
    @Environment(LocalStore.self) private var store: LocalStore?
    @State private var tab = Tab.image
    @State private var format = ShareImageFormat.portrait
    /// store が無いときの「機種名を隠す」
    @State private var localHidesModel = false
    /// 編集した初期文面。nil のあいだは、作った文面をそのまま使う
    @State private var editedCaption: String?
    /// 文面の欄を編集しているか。開いたときは選ばない（Mac はシートを開くと最初の入力欄が全文を選んだ状態になり、打った文字で消えてしまう）
    @FocusState private var editsCaption: Bool
    @State private var rendered: RenderedShareImage?
    /// 保存やコピーのあとに出す一言
    @State private var notice: String?
    #if os(macOS)
    @State private var exportsImage = false
    #endif
    @State private var device = ShareDeviceLabel.current
    private let price = MacUpgradePrice.current

    private static var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= Self.wideLayoutMinimumWidth
            ZStack {
                PaperBackground(wide: wide)
                ScrollView {
                    if wide {
                        wideLayout(height: proxy.size.height)
                    } else {
                        compactLayout(width: proxy.size.width)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .foregroundStyle(Theme.navy)
        .preferredColorScheme(.light)
        // 共有・保存・コピーに使う画像は、大きさと端末の表示が変わるたびに書き出し直す
        .task(id: RenderKey(format: format, device: deviceText)) {
            rendered = ShareImageRenderer.render(format: format, content: content)
        }
        #if os(macOS)
        .task {
            // Mac はシートを開くと、最初の入力欄（文面の欄）が全文を選んだ状態になる。打った文字で消えないよう、選ばない状態に戻す
            try? await Task.sleep(for: .milliseconds(100))
            editsCaption = false
        }
        #endif
        .onChange(of: hidesModel) {
            // 機種名を隠したら、機種名の入った文面を残さないよう、編集した文面も作り直す
            editedCaption = nil
        }
        #if os(macOS)
        .frame(minWidth: 900, idealWidth: 980, minHeight: 600, idealHeight: 700)
        .fileExporter(
            isPresented: $exportsImage,
            item: rendered.map { ShareImageFile(pngData: $0.pngData) },
            contentTypes: [.png],
            defaultFilename: ShareImageFile.fileName
        ) { result in
            switch result {
            case .success:
                announce(String(localized: "画像を保存しました"))
            case .failure:
                announce(String(localized: "画像を保存できませんでした"))
            }
        }
        #endif
    }

    // MARK: - 中身

    private struct RenderKey: Hashable {
        let format: ShareImageFormat
        let device: String
    }

    private var hidesModel: Bool {
        store?.hidesDeviceModelInShare ?? localHidesModel
    }

    private var hidesModelBinding: Binding<Bool> {
        Binding {
            hidesModel
        } set: { value in
            if let store {
                store.hidesDeviceModelInShare = value
            } else {
                localHidesModel = value
            }
        }
    }

    private var deviceText: String {
        device.text(hidesModel: hidesModel)
    }

    private var content: TributeStatementContent {
        TributeStatementContent(summary: summary, device: deviceText, price: price, isMac: Self.isMac)
    }

    private var link: URL? {
        ShareLinks.link(for: summary.mode)
    }

    private var postText: String {
        ShareText.post(summary, device: deviceText, price: price, link: link)
    }

    private var caption: String {
        editedCaption ?? ShareText.caption(summary, deviceName: device.shortName(hidesModel: hidesModel), price: price, link: link)
    }

    private var captionBinding: Binding<String> {
        Binding {
            caption
        } set: { value in
            editedCaption = value
        }
    }

    // MARK: - レイアウト

    private func compactLayout(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            tabBar
            switch tab {
            case .image:
                CanvasPreview(
                    format: format,
                    content: content,
                    maxWidth: max(0, min(width, 560) - 40),
                    maxHeight: format == .story ? 560 : .infinity
                )
                .frame(maxWidth: .infinity)
                options(showsFormat: true)
                captionEditor
                imageShareButton
                imageActions
            case .text:
                textPreview
                options(showsFormat: false)
                textShareButton
                RuleButton(title: "文字をコピー", action: copyText)
            }
            footnotes
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private func wideLayout(height: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 40) {
            CanvasPreview(format: format, content: content, maxWidth: 460, maxHeight: max(320, height - 56))
            VStack(alignment: .leading, spacing: 16) {
                header
                tabBar
                switch tab {
                case .image:
                    options(showsFormat: true)
                    captionEditor
                    imageShareButton
                    imageActions
                case .text:
                    textPreview
                    options(showsFormat: false)
                    textShareButton
                    RuleButton(title: "文字をコピー", action: copyText)
                }
                footnotes
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("明細書をシェア")
                .scaledFont(.mincho(22, .extraBold))
                .tracking(2.6)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            TextLink(title: "閉じる") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.image, title: "画像")
            Rectangle()
                .fill(Theme.navy)
                .frame(width: 1.5)
            tabButton(.text, title: "文字")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 3)
        .overlay(alignment: .top) { DoubleRule() }
        .overlay(alignment: .bottom) { DoubleRule() }
    }

    private func tabButton(_ value: Tab, title: LocalizedStringKey) -> some View {
        let selected = tab == value
        return Button {
            tab = value
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

// MARK: - 設定の欄と、共有・保存・コピー

extension SharePreviewScreen {
    private func options(showsFormat: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsFormat {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Text("大きさ")
                            .scaledFont(.mincho(15))
                        Spacer(minLength: 0)
                        formatOptions
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("大きさ")
                            .scaledFont(.mincho(15))
                        formatOptions
                    }
                }
                DashedRule()
            }
            Toggle(isOn: hidesModelBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("機種名を隠す")
                        .scaledFont(.mincho(15))
                    Text(verbatim: "→ \(device.text(hidesModel: true))")
                        .scaledFont(.mincho(12, .medium))
                        .foregroundStyle(Theme.subText)
                }
            }
            // Mac の既定はチェックボックスなので、設定の画面と同じスイッチにそろえる
            .toggleStyle(.switch)
            .tint(Theme.red)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .doubleFrame()
    }

    private var formatOptions: some View {
        HStack(spacing: 6) {
            formatOption(.portrait, title: "4:5 投稿用")
            formatOption(.story, title: "9:16 ストーリー用")
        }
    }

    private func formatOption(_ value: ShareImageFormat, title: LocalizedStringKey) -> some View {
        let selected = format == value
        return Button {
            format = value
        } label: {
            Text(title)
                .scaledFont(.typewriter(13))
                .lineLimit(1)
                .foregroundStyle(selected ? Theme.lightPaper : Theme.navy)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    if selected {
                        InkSurface(color: Theme.red)
                    }
                }
                .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1.5) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var captionEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("共有するときの文面（編集できます）")
                .scaledFont(.mincho(12))
                .foregroundStyle(Theme.subText)
            TextField("共有するときの文面", text: captionBinding, axis: .vertical)
                .focused($editsCaption)
                .scaledFont(.mincho(14, .medium))
                .lineLimit(2...6)
                .textFieldStyle(.plain)
                .padding(12)
                .background { InkSurface() }
                .overlay { DashedBorder() }
        }
    }

    private var textPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("共有する文字")
                .scaledFont(.mincho(12))
                .foregroundStyle(Theme.subText)
            Text(verbatim: postText)
                .scaledFont(.mincho(14, .medium))
                .lineSpacing(5)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background { InkSurface() }
                .overlay { DashedBorder() }
        }
    }

    // MARK: - 共有・保存・コピー

    @ViewBuilder private var imageShareButton: some View {
        if let rendered {
            ShareLink(
                item: ShareImageFile(pngData: rendered.pngData),
                message: Text(caption),
                preview: SharePreview("献上明細書", image: rendered.image)
            ) {
                PrimaryInkLabel(title: "共有する…", fontSize: 18, verticalPadding: 16)
            }
            .buttonStyle(.plain)
        } else {
            // 画像を書き出し終わるまでは押せない（すぐに終わる）
            Button {} label: {
                PrimaryInkLabel(title: "共有する…", fontSize: 18, verticalPadding: 16)
                    .opacity(0.5)
            }
            .buttonStyle(.plain)
            .disabled(true)
        }
    }

    private var textShareButton: some View {
        ShareLink(item: postText) {
            PrimaryInkLabel(title: "共有する…", fontSize: 18, verticalPadding: 16)
        }
        .buttonStyle(.plain)
    }

    private var imageActions: some View {
        HStack(spacing: 14) {
            RuleButton(title: "画像を保存", action: saveImage)
            #if os(macOS)
            RuleButton(title: "画像をコピー", action: copyImage)
            #endif
        }
        .disabled(rendered == nil)
    }

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice {
                Text(verbatim: notice)
                    .scaledFont(.mincho(13))
                    .foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("シェアには Game Center のニックネームは載りません。投稿は、選んだアプリからご自身で行います。")
                .scaledFont(.mincho(12, .medium))
                .foregroundStyle(Theme.subText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func saveImage() {
        guard let rendered else {
            return
        }
        #if os(macOS)
        exportsImage = true
        #else
        let data = rendered.pngData
        Task {
            do {
                try await PhotoLibrarySaver.save(pngData: data)
                announce(String(localized: "写真に保存しました"))
            } catch PhotoLibrarySaver.Failure.denied {
                announce(String(localized: "写真への追加が許可されていません。設定アプリの「Uncle RAM」から許可できます。"))
            } catch {
                announce(String(localized: "写真に保存できませんでした"))
            }
        }
        #endif
    }

    #if os(macOS)
    private func copyImage() {
        guard let rendered else {
            return
        }
        SharePasteboard.copy(image: rendered)
        announce(String(localized: "画像をコピーしました"))
    }
    #endif

    private func copyText() {
        SharePasteboard.copy(text: postText)
        announce(String(localized: "文字をコピーしました"))
    }

    private func announce(_ message: String) {
        notice = message
        AccessibilityNotification.Announcement(message).post()
    }
}

/// 明細書のプレビュー。書き出す画像と同じものを縮めて見せる（VoiceOver では明細書の項目を 1 行ずつ読める）
private struct CanvasPreview: View {
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
private struct DashedBorder: View {
    var body: some View {
        Rectangle()
            .strokeBorder(Theme.navy, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
    }
}

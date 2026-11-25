import SwiftUI

/// 設定（docs/SPEC.md「初回起動と設定」）。今の版で働く先がある項目だけを置く。
/// 振動（iPhone）・回収演出を控えめにする・使い方をもう一度見るは、振動・回収演出（#30）・吹き出し（#23）を入れるときに足す。
/// BGM と効果音の音量・購入を復元・翻訳の誤りを報告は段取り 4、プライバシーポリシーとサポートは紹介ページができたら足す
struct SettingsScreen: View {
    let onClose: () -> Void
    /// データの初期化（確認のあと）
    let onReset: () -> Void

    @Environment(LocalStore.self) private var store
    @State private var page: Page?
    @State private var confirmsReset = false

    enum Page {
        case memoryUsage
        case licenses
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    Ornament()
                    switch page {
                    case nil:
                        menu
                    case .memoryUsage:
                        MemoryUsagePage()
                    case .licenses:
                        LicensesPage()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .foregroundStyle(Theme.navy)
        .preferredColorScheme(.light)
        .confirmationDialog("端末の中の記録を消しますか？", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("消す", role: .destructive, action: onReset)
            Button("やめる", role: .cancel) {}
        } message: {
            Text("初回の案内・設定など、この端末の中の記録をすべて消します。Game Center に送った記録は消えません。")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(pageTitle)
                .scaledFont(.mincho(22, .extraBold))
                .tracking(2)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if page == nil {
                TextLink(title: "閉じる", action: onClose)
                    .keyboardShortcut(.cancelAction)
            } else {
                TextLink(title: "設定へ戻る") { page = nil }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    private var pageTitle: LocalizedStringKey {
        switch page {
        case nil: "設定"
        case .memoryUsage: "メモリの使い方について"
        case .licenses: "ライセンス"
        }
    }

    private var menu: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 18) {
            section("遊び方") {
                Toggle(isOn: $store.tapToDonate) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("タップで献上")
                            .scaledFont(.mincho(16))
                        Text(tapDescription)
                            .scaledFont(.mincho(13, .medium))
                            .foregroundStyle(Theme.subText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Theme.red)
            }
            section("資料") {
                pageLink("メモリの使い方について") { page = .memoryUsage }
                DashedRule()
                pageLink("ライセンス") { page = .licenses }
            }
            section("データ") {
                Button {
                    confirmsReset = true
                } label: {
                    Text("データの初期化")
                        .scaledFont(.mincho(16))
                        .foregroundStyle(Theme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text(verbatim: "Uncle RAM \(Self.version)")
                .scaledFont(.typewriter(11))
                .foregroundStyle(Theme.subText)
                .frame(maxWidth: .infinity)
        }
    }

    private var tapDescription: LocalizedStringKey {
        #if os(macOS)
        "長押しの代わりに、1 回目で献上を始め、もう一度で納品します（クリックかスペースキー）。ランキングは長押しと区別しません。"
        #else
        "長押しの代わりに、1 回目のタップで献上を始め、もう一度タップすると納品します。ランキングは長押しと区別しません。"
        #endif
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .scaledFont(.mincho(12, .extraBold))
                .tracking(3)
                .foregroundStyle(Theme.red)
            content()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .doubleFrame()
    }

    private func pageLink(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .scaledFont(.mincho(16))
                Spacer()
                Text(verbatim: "›")
                    .scaledFont(.mincho(18))
                    .foregroundStyle(Theme.subText)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 「1.0（12）」のような版とビルド番号
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(short)（\(build)）"
    }
}

/// 設定「メモリの使い方について」（文言は 2026-11-26 にユーザーが決定）
private struct MemoryUsagePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            paragraph("献上している間だけ、端末のメモリを実際に確保します。離すと、または回収されると、確保したメモリはすぐにすべて手放します。")
            paragraph("確保する量には上限があります。端末の残りのメモリが少なくなりすぎないよう、安全ラインの手前で必ず止まります。")
            paragraph("確保している間は、裏で開いているアプリが終了されることがあります。保存していない作業があるアプリは、先に保存しておいてください。")
            paragraph("メモリを手放しても、端末が速くなることはありません。")
            #if os(macOS)
            paragraph("使用可能なメモリの 60%（搭載メモリの 50% か 32GB まで）を、献上の枠にしています。")
            #endif
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .doubleFrame()
    }

    private func paragraph(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .scaledFont(.mincho(15))
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 設定「ライセンス」。書体（OFL）と画像の出典（docs/HANDOFF.md「素材の出典とライセンス」）
private struct LicensesPage: View {
    private struct Font: Identifiable {
        let name: String
        let licenseFile: String
        var id: String { name }
    }

    private struct ImageSource: Identifiable {
        let use: LocalizedStringKey
        let source: String
        let license: LocalizedStringKey
        var id: String { source }
    }

    private static let fonts = [
        Font(name: "Archivo Black", licenseFile: "OFL-ArchivoBlack"),
        Font(name: "Courier Prime", licenseFile: "OFL-CourierPrime"),
        Font(name: "Shippori Mincho B1", licenseFile: "OFL-ShipporiMinchoB1")
    ]

    private static let images = [
        ImageSource(use: "紙の背景", source: "Annie Spratt / Unsplash", license: "Unsplash License"),
        ImageSource(use: "飾り罫", source: "Ludvig S. Ipsen, Desk Book of Type, 1900 (Wikimedia Commons)", license: "パブリックドメイン"),
        ImageSource(use: "サーバーの網点", source: "Tony Marinescu / Unsplash", license: "Unsplash License"),
        ImageSource(
            use: "工場の網点",
            source: "Detroit Publishing Co., Homestead Steel Works, c. 1900 (Library of Congress)",
            license: "パブリックドメイン"
        ),
        ImageSource(
            use: "指差す手・シルクハット",
            source: "J. M. Flagg, I Want You for U.S. Army, 1917 (Library of Congress)",
            license: "パブリックドメイン"
        ),
        ImageSource(use: "回収飛行船", source: "Bain News Service, German dirigible, 1910 (Library of Congress)", license: "パブリックドメイン")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            panel("画像") {
                ForEach(Self.images) { image in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(image.use)
                            .scaledFont(.mincho(14))
                        Text(verbatim: image.source)
                            .scaledFont(.mincho(13, .medium))
                            .foregroundStyle(Theme.subText)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(image.license)
                            .scaledFont(.mincho(12, .medium))
                            .foregroundStyle(Theme.subText)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            panel("書体（SIL Open Font License 1.1）") {
                ForEach(Self.fonts) { font in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: font.name)
                            .scaledFont(.mincho(15))
                        Text(verbatim: Self.licenseText(font.licenseFile))
                            .scaledFont(.typewriter(10))
                            .foregroundStyle(Theme.subText)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if font.id != Self.fonts.last?.id {
                        DashedRule()
                    }
                }
            }
        }
    }

    private func panel(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .scaledFont(.mincho(12, .extraBold))
                .tracking(2)
                .foregroundStyle(Theme.red)
            content()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .doubleFrame()
    }

    /// 同梱した OFL.txt（`Tools/fonts/subset.py` が google/fonts から取ってくる）
    private static func licenseText(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

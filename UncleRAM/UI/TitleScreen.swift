import SwiftUI

/// タイトル画面。iPhone は docs/design/Main.png（390 × 844）、Mac と広い iPad は docs/design/MacMain.png（1200 × 760）に合わせる。
/// 主ボタンは速達便（docs/SPEC.md「プレイモード」）。行き先の画面がまだ無いリンクとボタン（強化・ランキング・定期便・取引先）は、
/// 画面ができたときに足す（2026-11-26 にユーザーが決定）
struct TitleScreen: View {
    let onStartExpress: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let wide = proxy.size.width >= RoundScreen.wideLayoutMinimumWidth
            ZStack {
                PaperBackground(wide: wide)
                if wide {
                    WideTitleLayout(onStartExpress: onStartExpress, onOpenSettings: onOpenSettings)
                } else {
                    // 低い画面や、文字を大きくしたとき（Dynamic Type）は縦に送れるようにする。収まるときは下の注記を画面の下に寄せる
                    ScrollView {
                        CompactTitleLayout(height: proxy.size.height, onStartExpress: onStartExpress, onOpenSettings: onOpenSettings)
                            .frame(maxWidth: 480)
                            .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
        }
        .preferredColorScheme(.light)
    }
}

/// タイトルに出す、搭載メモリへの会長の一言（docs/SPEC.md「ネタの詰め込み方」）
enum ChairmanGreeting: Equatable {
    /// 「……まあ、いいでしょう」
    case modest
    /// 「上客様がお見えです」
    case honored

    /// ランキングのメモリのクラスでいちばん小さいとき（iPhone・iPad は 8GB 以下、Mac は 16GB 以下）は modest、
    /// それより大きいときは honored（2026-11-26 にユーザーが決定）
    static func forInstalledMemory(gigabytes: Int, isMac: Bool) -> ChairmanGreeting {
        gigabytes <= (isMac ? 16 : 8) ? .modest : .honored
    }

    static var current: ChairmanGreeting {
        #if os(macOS)
        forInstalledMemory(gigabytes: DeviceDescription.installedGigabytes, isMac: true)
        #else
        forInstalledMemory(gigabytes: DeviceDescription.installedGigabytes, isMac: false)
        #endif
    }

    var line: LocalizedStringKey {
        switch self {
        case .modest: "マロック会長「……まあ、いいでしょう」"
        case .honored: "マロック会長「上客様がお見えです」"
        }
    }
}

/// 「この端末の搭載メモリ（実測）」の欄
struct InstalledMemoryCard: View {
    var labelSize: CGFloat = 11
    var lineSize: CGFloat = 13
    var numberSize: CGFloat = 30

    private var label: LocalizedStringKey {
        #if os(macOS)
        "この Mac の搭載メモリ（実測）"
        #else
        "この端末の搭載メモリ（実測）"
        #endif
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .scaledFont(.typewriter(labelSize))
                    .foregroundStyle(Theme.red)
                Text(ChairmanGreeting.current.line)
                    .scaledFont(.mincho(lineSize, .medium))
                    .foregroundStyle(Theme.subText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: "\(DeviceDescription.installedGigabytes)")
                    .font(Theme.display(numberSize))
                Text(verbatim: "GB")
                    .font(Theme.display(numberSize / 2))
            }
            .fixedSize()
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .background(Theme.lightPaper.opacity(0.6))
        .overlay {
            Rectangle().strokeBorder(Theme.navy, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
        .accessibilityElement(children: .combine)
    }
}

/// 「本作は架空の企業を描いたゲームです。端末の性能を上げる機能はありません。」（審査 1.1.6）
struct FictionDisclaimer: View {
    var singleLine = false
    var fontSize: CGFloat = 11

    var body: some View {
        Group {
            if singleLine {
                Text("本作は架空の企業を描いたゲームです。端末の性能を上げる機能はありません。")
            } else {
                Text("本作は架空の企業を描いたゲームです。\n端末の性能を上げる機能はありません。")
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .scaledFont(.mincho(fontSize, .medium))
        .foregroundStyle(Theme.subText)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// iPhone（と、狭い iPad）のタイトル
private struct CompactTitleLayout: View {
    let height: CGFloat
    let onStartExpress: () -> Void
    let onOpenSettings: () -> Void

    /// iPhone SE のように低い画面では、指差す手の絵を低くする
    private var isShort: Bool {
        height < 760
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                CorporateMasthead(hatSize: CGSize(width: 34, height: 22), fontSize: 11)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 縦に送れる中では高さを伸び縮みさせても縮まないので、低い画面では絵の高さを決めて小さくする（主ボタンを最初の画面に収める）
            RecruitPoster(imageHeight: isShort ? 120...120 : 212...212, headlineSize: isShort ? 34 : 42, showsStation: true)
            VStack(spacing: 2) {
                Text(verbatim: "Uncle RAM")
                    .font(Theme.display(30))
                Text("アンクル・ラム ― 回収されるまで、差し出せ。")
                    .scaledFont(.mincho(13, .medium))
                    .foregroundStyle(Theme.subText)
                    .multilineTextAlignment(.center)
            }
            InstalledMemoryCard()
            Spacer(minLength: 8)
            PrimaryInkButton(title: "献上をはじめる", fontSize: 17, verticalPadding: 15, action: onStartExpress)
                .keyboardShortcut(.defaultAction)
            // デザインは「強化 ✦ ランキング ✦ 設定」。強化とランキングは、行き先の画面ができたら並べる
            TextLink(title: "設定", action: onOpenSettings)
            FictionDisclaimer()
        }
        .padding(.horizontal, 20)
        .padding(.top, isShort ? 8 : 16)
        .padding(.bottom, 18)
        .foregroundStyle(Theme.navy)
    }
}

/// Mac（と、広い iPad）のタイトル。右の列（本日のデイリー・前回のご提供）は、デイリーをつなぐときに足す
private struct WideTitleLayout: View {
    let onStartExpress: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                CorporateMasthead()
                Spacer()
                // デザインは「強化・ランキング・設定」。強化とランキングは、行き先の画面ができたら並べる
                TextLink(title: "設定", action: onOpenSettings)
                    .keyboardShortcut(",", modifiers: .command)
            }
            Ornament()
            HStack(alignment: .center, spacing: 36) {
                RecruitPoster(imageHeight: 160...400, headlineSize: 42, showsStation: true)
                    .frame(width: 330)
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: "Uncle RAM")
                            .font(Theme.display(64))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("アンクル・ラム ― 回収されるまで、差し出せ。")
                            .scaledFont(.mincho(16, .medium))
                            .foregroundStyle(Theme.subText)
                    }
                    InstalledMemoryCard(labelSize: 12, lineSize: 15, numberSize: 44)
                    PrimaryInkButton(title: "献上をはじめる", caption: "速達便 · 約 20 秒", fontSize: 20, verticalPadding: 16, action: onStartExpress)
                        .keyboardShortcut(.defaultAction)
                }
                .frame(maxWidth: 480)
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
            HStack {
                FictionDisclaimer(singleLine: true, fontSize: 12)
                Spacer()
                #if os(macOS)
                Text("return: 献上をはじめる · ⌘, : 設定")
                    .scaledFont(.typewriter(12))
                    .foregroundStyle(Theme.subText)
                #endif
            }
            .padding(.top, 8)
            .overlay(alignment: .top) { DashedRule() }
        }
        .padding(.horizontal, 36)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .foregroundStyle(Theme.navy)
    }
}

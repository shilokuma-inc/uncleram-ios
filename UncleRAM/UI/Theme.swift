import SwiftUI

/// 色と書体。docs/HANDOFF.md「デザインの実装メモ」。
///
/// 書体は試作では OS に入っているもので代わりにしている（数字と英字の見出し: システムの Black、タイプライター風: Courier New、
/// 日本語の本文: ヒラギノ明朝）。Google Fonts の書体（Archivo Black・Courier Prime・Shippori Mincho B1 など）は、
/// 使う文字に絞って同梱する段取り（速達便が遊べる版）で入れる。
enum Theme {
    /// 紙
    static let paper = Color(hex: 0xEDE4CF)
    /// 明るい紙
    static let lightPaper = Color(hex: 0xF8F3E6)
    /// 紺（文字）
    static let navy = Color(hex: 0x1E2340)
    /// 赤
    static let red = Color(hex: 0xB8322B)
    /// 薄い文字
    static let subText = Color(hex: 0x3F4257)
    /// 青（ずれの色）
    static let blue = Color(hex: 0x3D5A99)

    /// 数字と英字の見出し（Archivo Black の代わり）
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black)
    }

    /// タイプライター風の値（Courier Prime の代わり）
    static func typewriter(_ size: CGFloat) -> Font {
        .custom("CourierNewPS-BoldMT", fixedSize: size)
    }

    /// 日本語の本文（Shippori Mincho B1 の代わり）
    static func mincho(_ size: CGFloat, bold: Bool = true) -> Font {
        .custom(bold ? "HiraMinProN-W6" : "HiraMinProN-W3", fixedSize: size)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// 紙の背景（画面全体）。横長の画面では、元画像から切り抜き直した横長の紙を使う
struct PaperBackground: View {
    var wide = false

    var body: some View {
        Theme.paper
            .overlay {
                Image(wide ? .paperWide : .paperBackground)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .ignoresSafeArea()
    }
}

/// 紙の質感を乗算で重ねた面（明るい紙・赤・紺の面）
struct InkSurface: View {
    var color: Color = Theme.lightPaper

    var body: some View {
        color
            .overlay {
                Image(.paperBackground)
                    .resizable()
                    .scaledToFill()
                    .blendMode(.multiply)
            }
            .clipped()
    }
}

/// 紺の二重の枠（外の線 1.5pt と、6pt 内側の 1pt の線）
struct DoubleFrame: ViewModifier {
    var inset: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .background { InkSurface() }
            .overlay {
                Rectangle().strokeBorder(Theme.navy, lineWidth: 1.5)
            }
            .overlay {
                Rectangle().strokeBorder(Theme.navy, lineWidth: 1).padding(inset)
            }
    }
}

extension View {
    func doubleFrame(inset: CGFloat = 6) -> some View {
        modifier(DoubleFrame(inset: inset))
    }
}

/// 数字の書式
enum Formatters {
    /// 3,072 のような桁区切り（MB は 1,048,576 バイト）
    static func megabytes(_ bytes: UInt64) -> String {
        (Double(bytes) / 1_048_576).rounded(.down).formatted(.number.precision(.fractionLength(0)))
    }

    /// 0.62 → 62
    static func percent(_ fraction: Double) -> String {
        (fraction * 100).rounded().formatted(.number.precision(.fractionLength(0)))
    }

    static func integer(_ value: Int) -> String {
        value.formatted(.number)
    }
}

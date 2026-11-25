import CoreText
import SwiftUI

/// 色と書体。docs/HANDOFF.md「デザインの実装メモ」。
///
/// 書体は `UncleRAM/Fonts/` に同梱し、Info.plist（iOS は `UIAppFonts`、Mac は `ATSApplicationFontsPath`）で読み込む。
/// 日本語の書体は文言に出てくる文字だけに絞ってあるので、文言を変えたら `uv run Tools/fonts/subset.py` で作り直す
/// （足りない文字は FontTests が見つける）。
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

    /// 日本語の本文の太さ。デザインは Shippori Mincho B1 の 500・700・800 を使う
    nonisolated enum MinchoWeight: CaseIterable {
        /// 500。説明や注記
        case medium
        /// 700。ふつうの本文と見出し
        case bold
        /// 800。ボタン・判子・合計など、いちばん強く見せるところ
        case extraBold

        var postScriptName: String {
            switch self {
            case .medium: "ShipporiMinchoB1-Medium"
            case .bold: "ShipporiMinchoB1-Bold"
            case .extraBold: "ShipporiMinchoB1-ExtraBold"
            }
        }
    }

    /// 数字と英字の見出し（Archivo Black）
    static func display(_ size: CGFloat) -> Font {
        .custom(FontName.archivoBlack, fixedSize: size)
    }

    /// タイプライター風の値（Courier Prime の Bold）。Courier Prime に無い和文の文字は、
    /// デザイン（`'Courier Prime', 'Shippori Mincho B1'`）と同じく Shippori Mincho B1 の Bold で出す
    static func typewriter(_ size: CGFloat) -> Font {
        Font(cascading(FontName.courierPrimeBold, fallback: MinchoWeight.bold.postScriptName, size: size))
    }

    /// 日本語の本文（Shippori Mincho B1）
    static func mincho(_ size: CGFloat, _ weight: MinchoWeight = .bold) -> Font {
        .custom(weight.postScriptName, fixedSize: size)
    }

    /// 回収の大見出し（Dela Gothic One。日本語だけ）
    static func heading(_ size: CGFloat) -> Font {
        .custom(FontName.delaGothicOne, fixedSize: size)
    }

    /// 同梱した書体の PostScript 名
    nonisolated enum FontName {
        static let archivoBlack = "ArchivoBlack-Regular"
        static let courierPrimeBold = "CourierPrime-Bold"
        static let delaGothicOne = "DelaGothicOne-Regular"
    }

    /// `name` に無い文字を `fallback` で出す書体（指定しないと、OS の書体で出てしまう）
    private static func cascading(_ name: String, fallback: String, size: CGFloat) -> CTFont {
        let attributes: [CFString: Any] = [
            kCTFontNameAttribute: name,
            kCTFontCascadeListAttribute: [CTFontDescriptorCreateWithNameAndSize(fallback as CFString, size)]
        ]
        return CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), size, nil)
    }
}

extension Theme {
    /// Dynamic Type に合わせて大きくする文字の書体（説明・台詞・ラベル）
    enum ScaledText {
        case mincho(CGFloat, MinchoWeight = .bold)
        case typewriter(CGFloat)
    }
}

extension View {
    /// 説明・台詞・ラベルの書体。Dynamic Type に合わせて、本文（body）と同じ割合で大きくする。
    /// 大きな数字・ボタンの中・判子・絵に添えた文字は、レイアウトを保つため `.font(Theme.…)` のまま大きさを変えない。
    /// 大きくするのは「さらに大きな文字」を使わない範囲（xxxLarge）まで（2026-11-26 にユーザーが決定。UncleRAM.swift で上限を決める）
    func scaledFont(_ text: Theme.ScaledText) -> some View {
        modifier(ScaledFontModifier(text: text))
    }
}

private struct ScaledFontModifier: ViewModifier {
    let text: Theme.ScaledText
    @ScaledMetric private var size: CGFloat

    init(text: Theme.ScaledText) {
        self.text = text
        switch text {
        case let .mincho(size, _), let .typewriter(size):
            _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        }
    }

    func body(content: Content) -> some View {
        switch text {
        case let .mincho(_, weight):
            content.font(Theme.mincho(size, weight))
        case .typewriter:
            content.font(Theme.typewriter(size))
        }
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
                    // 枠より大きく広げた画像は、見た目は切り抜いてもタップの判定が枠の外に残るので、判定から外す
                    .allowsHitTesting(false)
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
                    // 枠より大きく広げた画像が、近くのボタン（右上の「計測」など）のタップを吸い取らないようにする
                    .allowsHitTesting(false)
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

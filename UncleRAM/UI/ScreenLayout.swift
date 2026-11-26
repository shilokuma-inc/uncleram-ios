import SwiftUI

/// 画面の組み方。Mac の横長のレイアウトと、iPhone のレイアウトのどちらで組み、どれだけ拡大するか。
///
/// 横幅が広いときは横長のレイアウトにする（2026-11-12 にユーザーが決定）。iPad の縦向きのような縦長の画面は、幅が広くても
/// iPhone のレイアウトにする（2026-11-26。横長のレイアウトでは下が空くため）。
/// iPad では、どちらのレイアウトも、デザインより大きい画面では画面の大きさに合わせて拡大する（iPhone のレイアウトのままでは小さく見えるため）。
/// Mac はウィンドウの最小幅が 1000 なので、いつも横長のレイアウトになり、ウィンドウを広げても拡大しない（広げた分は中央の列が伸びる）
struct ScreenLayout: Equatable {
    /// これより広く、縦長でないときは、横長のレイアウトにする（Mac のデザインの最小幅 1000 に近い値）
    static let wideMinimumWidth: CGFloat = 960
    /// iPhone のレイアウトを拡大するとき、拡大する前に取る大きさ。中身の最大幅（480）に左右の余白を足した幅と、
    /// iPhone の大きい機種ほどの高さ。これより広く高い画面では、この大きさで組んでから画面いっぱいに拡大する
    static let compactReferenceSize = CGSize(width: 540, height: 880)
    /// 横長のレイアウトを拡大するとき、拡大する前に取る大きさ（Mac のデザインの大きさ）
    static let wideReferenceSize = CGSize(width: 1200, height: 760)
    /// 拡大する上限
    static let maximumScale: CGFloat = 1.6

    /// 横長のレイアウトにするか
    let isWide: Bool
    /// レイアウトの拡大率。Mac と、デザインほどの大きさの画面（iPhone など）では 1
    let scale: CGFloat

    /// - Parameters:
    ///   - size: 画面（ウィンドウ）の、安全な領域の大きさ
    ///   - compactReferenceHeight: iPhone のレイアウトを拡大する前に取る高さ。中身が高い画面（タイトル）は大きくする
    init(size: CGSize, compactReferenceHeight: CGFloat = Self.compactReferenceSize.height) {
        #if os(macOS)
        isWide = size.width >= Self.wideMinimumWidth
        scale = 1
        #else
        isWide = size.width >= Self.wideMinimumWidth && size.width >= size.height
        let reference = isWide ? Self.wideReferenceSize : CGSize(width: Self.compactReferenceSize.width, height: compactReferenceHeight)
        scale = Self.scale(fitting: reference, in: size)
        #endif
    }

    /// `reference` の大きさで組んだものを、`size` に収まるだけ拡大する倍率（1 から `maximumScale` まで）
    static func scale(fitting reference: CGSize, in size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else {
            return 1
        }
        let scale = min(size.width / reference.width, size.height / reference.height)
        return min(max(scale, 1), maximumScale)
    }

    /// レイアウトを組む大きさ（拡大する前の大きさ）
    func layoutSize(in size: CGSize) -> CGSize {
        CGSize(width: size.width / scale, height: size.height / scale)
    }
}

extension View {
    /// 拡大する前の大きさ（`ScreenLayout.layoutSize(in:)`）で組んでから、`size` いっぱいに拡大する。
    /// 拡大率が 1 のときも同じ形で包む（Split View で幅を変えたときに、画面の状態が作り直されないように）
    func scaledToLayout(_ layout: ScreenLayout, in size: CGSize) -> some View {
        let layoutSize = layout.layoutSize(in: size)
        return frame(width: layoutSize.width, height: layoutSize.height)
            .scaleEffect(layout.scale)
            .frame(width: size.width, height: size.height)
    }
}

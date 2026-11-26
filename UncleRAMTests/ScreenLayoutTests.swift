import CoreGraphics
import Testing
@testable import UncleRAM

/// 画面の組み方（横長のレイアウトか、iPhone のレイアウトか）と拡大率
@MainActor
struct ScreenLayoutTests {
    #if os(iOS)
    /// iPhone は、大きい機種でも iPhone のレイアウトを拡大しない
    @Test(arguments: [CGSize(width: 375, height: 647), CGSize(width: 402, height: 778), CGSize(width: 440, height: 868)])
    func iPhoneIsCompactWithoutScaling(size: CGSize) {
        let layout = ScreenLayout(size: size)
        #expect(!layout.isWide)
        #expect(layout.scale == 1)
    }

    /// iPad の縦向きは、幅が 960 を越えても（13 インチ）iPhone のレイアウトにし、画面の高さに合わせて拡大する
    @Test func iPadPortraitIsScaledCompact() {
        let large = ScreenLayout(size: CGSize(width: 1032, height: 1332))
        #expect(!large.isWide)
        #expect(abs(large.scale - 1332.0 / 880) < 0.001)
        let small = ScreenLayout(size: CGSize(width: 834, height: 1166))
        #expect(!small.isWide)
        #expect(abs(small.scale - 1166.0 / 880) < 0.001)
        // 拡大する前の大きさは、iPhone の大きい機種ほどの高さになる
        #expect(abs(large.layoutSize(in: CGSize(width: 1032, height: 1332)).height - 880) < 0.001)
    }

    /// タイトルは中身が高いので、拡大する前に取る高さを大きくして、拡大を控えめにする
    @Test func titleUsesTallerReference() {
        let layout = ScreenLayout(size: CGSize(width: 1032, height: 1332), compactReferenceHeight: 1_000)
        #expect(abs(layout.scale - 1.332) < 0.001)
    }

    /// iPad の横向きは横長のレイアウトにし、Mac のデザイン（1200 × 760）より大きい画面では拡大する
    @Test func iPadLandscapeIsWide() {
        let large = ScreenLayout(size: CGSize(width: 1376, height: 988))
        #expect(large.isWide)
        #expect(abs(large.scale - 1376.0 / 1200) < 0.001)
        let small = ScreenLayout(size: CGSize(width: 1210, height: 790))
        #expect(small.isWide)
        #expect(abs(small.scale - 1210.0 / 1200) < 0.001)
    }

    /// Split View などで幅が狭いときは、iPhone のレイアウトにする（高さがあっても、幅に合わせて拡大は控える）
    @Test(arguments: [CGSize(width: 320, height: 1166), CGSize(width: 678, height: 988), CGSize(width: 940, height: 700)])
    func narrowWindowIsCompact(size: CGSize) {
        let layout = ScreenLayout(size: size)
        #expect(!layout.isWide)
        #expect(layout.scale >= 1)
        #expect(layout.scale <= max(1, size.width / ScreenLayout.compactReferenceSize.width))
    }
    #endif

    #if os(macOS)
    /// Mac はいつも横長のレイアウトで、ウィンドウを広げても、縦長にしても拡大しない
    @Test(arguments: [
        CGSize(width: 1000, height: 612),
        CGSize(width: 1200, height: 732),
        CGSize(width: 1800, height: 1100),
        CGSize(width: 1000, height: 1200)
    ])
    func macIsWideWithoutScaling(size: CGSize) {
        let layout = ScreenLayout(size: size)
        #expect(layout.isWide)
        #expect(layout.scale == 1)
    }
    #endif

    /// 拡大率は 1 から上限（1.6）までに収める
    @Test func scaleIsClamped() {
        #expect(ScreenLayout.scale(fitting: CGSize(width: 540, height: 880), in: CGSize(width: 300, height: 500)) == 1)
        let huge = CGSize(width: 5_000, height: 5_000)
        #expect(ScreenLayout.scale(fitting: CGSize(width: 540, height: 880), in: huge) == ScreenLayout.maximumScale)
        #expect(ScreenLayout.scale(fitting: CGSize(width: 540, height: 880), in: .zero) == 1)
    }
}

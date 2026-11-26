import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// シェア画像の大きさ（docs/SPEC.md「共有機能」）。4:5（1080×1350）が基本で、ストーリー用の 9:16（1080×1920）も選べる
nonisolated enum ShareImageFormat: String, CaseIterable, Sendable, Identifiable {
    /// 4:5 投稿用。支給と控除を横に並べる
    case portrait
    /// 9:16 ストーリー用。明細書を縦に積む
    case story

    var id: String {
        rawValue
    }

    /// 描くときの大きさ（pt）。`scale` をかけると、ちょうど書き出す画素数になる
    var canvasSize: CGSize {
        switch self {
        case .portrait:
            CGSize(width: 540, height: 675)
        case .story:
            CGSize(width: 432, height: 768)
        }
    }

    var scale: CGFloat {
        switch self {
        case .portrait:
            2
        case .story:
            2.5
        }
    }

    /// 書き出す画素数
    var pixelSize: CGSize {
        CGSize(width: canvasSize.width * scale, height: canvasSize.height * scale)
    }
}

/// シェア画像の 1 枚。紙の上に、社名・明細書・会長の一言を置く。画像は書き出すときも、プレビューでも同じものを描く
struct ShareImageCanvas: View {
    let format: ShareImageFormat
    let content: TributeStatementContent
    /// 紙の背景を敷くか。リプレイ動画の最後（`ReplayEndCard`）は、縮めて下に「#UncleRAM」を置くので、背景を外に敷く
    var showsPaper = true

    var body: some View {
        VStack(spacing: format == .story ? 16 : 12) {
            if format == .story {
                Spacer(minLength: 0)
            }
            masthead
            CanvasOrnament()
            TributeStatement(content: content, twoColumns: format == .portrait)
                // 上下の Spacer に高さを取られて、縮められる文字が小さくされないよう、明細書は本来の高さで置く
                .fixedSize(horizontal: false, vertical: true)
                .rotationEffect(.degrees(-0.6))
                .padding(.top, 4)
            Text(chairmanLine)
                .font(Theme.mincho(format == .story ? 15 : 14, .medium))
                .foregroundStyle(Theme.subText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, format == .story ? 18 : 24)
        .padding(.top, format == .story ? 24 : 22)
        .padding(.bottom, format == .story ? 24 : 16)
        .frame(width: format.canvasSize.width, height: format.canvasSize.height)
        .background {
            if showsPaper {
                PaperBackground()
            }
        }
        .clipped()
        .foregroundStyle(Theme.navy)
        // 画像は固定のレイアウトにする。文字の大きさの設定で、プレビューと書き出した画像がずれないように
        .environment(\.dynamicTypeSize, .large)
        .environment(\.colorScheme, .light)
    }

    /// 社名と社是（文字の大きさを変えない版。タイトルの `CorporateMasthead` は Dynamic Type で大きくなる）
    private var masthead: some View {
        let size: CGFloat = format == .story ? 12 : 14
        return HStack(spacing: size * 0.9) {
            Image(.hatHalftone)
                .resizable()
                .scaledToFit()
                .frame(width: size * 3.1, height: size * 2.1)
                .accessibilityHidden(true)
            Text(verbatim: "ALLOCATE CORP.")
                .font(Theme.typewriter(size))
                .tracking(size * 0.08)
            Text("全人類の RAM を、ひとつの AI に。")
                .font(Theme.mincho(size))
                .tracking(size * 0.04)
                .foregroundStyle(Theme.red)
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var chairmanLine: LocalizedStringKey {
        content.summary.isCollected ? "「ご提供、誠にありがとうございました。」" : "「次回はもう少し、お願いできますね？」"
    }
}

/// シェア画像の上の飾り罫（`Ornament` と同じ絵）
private struct CanvasOrnament: View {
    var body: some View {
        Canvas { context, size in
            let image = context.resolve(Image(.borderA))
            let natural = image.size
            guard natural.height > 0 else {
                return
            }
            let width = natural.width * size.height / natural.height
            var x: CGFloat = 0
            while x < size.width {
                context.draw(image, in: CGRect(x: x, y: 0, width: width, height: size.height))
                x += width
            }
        }
        .frame(height: 12)
        .clipped()
        .opacity(0.85)
        .accessibilityHidden(true)
    }
}

/// 書き出したシェア画像
struct RenderedShareImage {
    let format: ShareImageFormat
    let cgImage: CGImage
    /// PNG（共有・保存・コピーに使う）
    let pngData: Data

    var image: Image {
        Image(decorative: cgImage, scale: 1)
    }
}

/// ImageRenderer でシェア画像を書き出す
enum ShareImageRenderer {
    static func render(format: ShareImageFormat, content: TributeStatementContent) -> RenderedShareImage? {
        let renderer = ImageRenderer(content: ShareImageCanvas(format: format, content: content))
        renderer.proposedSize = ProposedViewSize(format.canvasSize)
        renderer.scale = format.scale
        renderer.isOpaque = true
        guard let cgImage = renderer.cgImage, let pngData = pngData(of: cgImage) else {
            return nil
        }
        return RenderedShareImage(format: format, cgImage: cgImage, pngData: pngData)
    }

    nonisolated static func pngData(of image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }
}

/// 共有シートと、Mac の「画像を保存」に渡す PNG
nonisolated struct ShareImageFile: Transferable, Sendable {
    static let fileName = "UncleRAM-statement.png"

    let pngData: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { file in
            file.pngData
        }
        .suggestedFileName(fileName)
    }
}

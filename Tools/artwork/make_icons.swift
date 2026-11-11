// 引き継ぎ資料のアプリアイコン（1024px・通常・ダーク・色付き）から、アセットカタログの AppIcon を作る。
//
//   swiftc -O Tools/artwork/make_icons.swift -o /tmp/make_icons
//   /tmp/make_icons <通常.png> <ダーク.png> <色付き.png> UncleRAM/Assets.xcassets/AppIcon.appiconset
//
// - iPhone・iPad: 1024px の 1 枚ずつ。App Store はアルファのあるアイコンを受け付けないので、不透明の RGB で描き直す
// - Mac: 16〜1024px（@1x・@2x）。Mac は OS がアイコンを角丸に切り抜かないので、Apple の Mac のアイコンの
//   グリッド（1024 の中に 824 の角丸の四角、角の半径 185.4）に合わせて縮め、まわりを透明にする

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func load(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("読み込めません: \(path)")
    }
    return image
}

func save(_ image: CGImage, _ path: String) {
    guard let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        fatalError("書き出せません: \(path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("書き出せません: \(path)") }
}

func context(_ size: Int, opaque: Bool) -> CGContext {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: size,
              height: size,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: space,
              bitmapInfo: info
          ) else {
        fatalError("描画の準備に失敗しました")
    }
    context.interpolationQuality = .high
    return context
}

/// iPhone・iPad 用。アルファの無い 1024px にする
func opaqueIcon(_ image: CGImage) -> CGImage {
    let canvas = context(1024, opaque: true)
    canvas.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    return canvas.makeImage()!
}

/// Mac 用。1024 の中の 824 の角丸の四角に縮め、まわりを透明にしてから size に縮める
func macIcon(_ image: CGImage, size: Int) -> CGImage {
    let canvas = context(size, opaque: false)
    let scale = CGFloat(size) / 1024
    let body = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let radius = 185.4 * scale
    canvas.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
    canvas.clip()
    canvas.draw(image, in: body)
    return canvas.makeImage()!
}

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    print("usage: make_icons <通常.png> <ダーク.png> <色付き.png> <AppIcon.appiconset>")
    exit(1)
}
let (light, dark, tinted, output) = (load(arguments[1]), load(arguments[2]), load(arguments[3]), arguments[4])

save(opaqueIcon(light), "\(output)/AppIcon.png")
save(opaqueIcon(dark), "\(output)/AppIcon-Dark.png")
save(opaqueIcon(tinted), "\(output)/AppIcon-Tinted.png")

var macImages: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "AppIcon-mac-\(points)@\(scale)x.png"
        save(macIcon(light, size: points * scale), "\(output)/\(name)")
        macImages.append("""
            {
              "filename" : "\(name)",
              "idiom" : "mac",
              "scale" : "\(scale)x",
              "size" : "\(points)x\(points)"
            }
        """)
    }
}

let iosImages = [
    ("AppIcon.png", nil),
    ("AppIcon-Dark.png", "dark"),
    ("AppIcon-Tinted.png", "tinted")
].map { filename, appearance -> String in
    let appearances = appearance.map {
        """
        ,
              "appearances" : [
                {
                  "appearance" : "luminosity",
                  "value" : "\($0)"
                }
              ]
        """
    } ?? ""
    return """
        {
          "filename" : "\(filename)",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"\(appearances)
        }
    """
}

let contents = """
{
  "images" : [
\((iosImages + macImages).joined(separator: ",\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
do {
    try contents.write(toFile: "\(output)/Contents.json", atomically: true, encoding: .utf8)
    print("AppIcon を書き出しました: \(output)")
} catch {
    fatalError("Contents.json を書き出せません: \(error)")
}

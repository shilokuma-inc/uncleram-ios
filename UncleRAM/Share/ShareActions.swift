import Foundation
#if os(iOS)
import Photos
import UIKit
#else
import AppKit
#endif

/// 「文字をコピー」「画像をコピー」（Mac）のクリップボード
enum SharePasteboard {
    static func copy(text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #endif
    }

    #if os(macOS)
    /// 画像を PNG と TIFF の両方で置く（TIFF しか読まないアプリにも貼れるように）
    static func copy(image: RenderedShareImage) {
        let item = NSPasteboardItem()
        item.setData(image.pngData, forType: .png)
        let size = NSSize(width: image.cgImage.width, height: image.cgImage.height)
        if let tiff = NSImage(cgImage: image.cgImage, size: size).tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
    #endif
}

#if os(iOS)
/// iPhone・iPad の「画像を保存」「動画を保存」。写真への追加だけの許可（NSPhotoLibraryAddUsageDescription）で、写真ライブラリに書き足す。
/// 写真を読む許可は求めない
nonisolated enum PhotoLibrarySaver {
    enum Failure: Error {
        /// 写真への追加が許可されていない
        case denied
    }

    static func save(pngData: Data) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw Failure.denied
        }
        // 変更の処理は写真ライブラリの裏のキューで呼ばれるので、MainActor の外（nonisolated）で作る
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: pngData, options: nil)
        }
    }

    /// 「動画を保存」。ファイルは写真ライブラリに写す（元のファイルは、共有のプレビューを閉じたときに消す）
    static func save(videoAt url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw Failure.denied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: url, options: nil)
        }
    }
}
#endif

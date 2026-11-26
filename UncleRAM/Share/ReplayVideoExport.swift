import CoreTransferable
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// 書き出したリプレイ動画
struct ReplayVideo: Equatable {
    let url: URL
    /// 長さ（秒）
    let duration: Double

    static func == (lhs: ReplayVideo, rhs: ReplayVideo) -> Bool {
        lhs.url == rhs.url
    }
}

/// 記録からリプレイ動画を作る（docs/SPEC.md「共有機能」の動画）。絵は ImageRenderer で 1 コマずつ描き（メインスレッド）、
/// 書き出しの係（`ReplayVideoEncoder`、別のスレッド）に渡して、描き終えた絵はすぐに手放す。
/// 1 コマ描くあいだに、前のコマを書き出しの係が書く。結果の画面から開くので、このときメモリはもう解放してある
enum ReplayVideoMaker {
    /// - Parameter progress: 0〜1。1 コマ書くたびに呼ぶ
    static func make(
        script: ReplayScript,
        content: TributeStatementContent,
        to url: URL,
        bundle: Bundle = .main,
        progress: (Double) -> Void = { _ in }
    ) async throws -> ReplayVideo {
        let timeline = ReplayTimeline(script: script)
        let cues = timeline.soundCues
        let duration = timeline.totalDuration
        let audio = try await Task.detached(priority: .userInitiated) {
            try ReplayAudioMixer.mix(cues: cues, duration: duration, bundle: bundle)
        }.value
        let encoder = try ReplayVideoEncoder(url: url, audio: audio)
        do {
            var previous: (frame: ReplayFrame, image: ReplayFrameImage)?
            var pending: Task<Void, any Error>?
            for index in 0..<timeline.frameCount {
                try Task.checkCancellation()
                let frame = timeline.frame(at: index)
                // 前のコマと同じ絵（押す前・判子のあと・明細書）は、描き直さない
                let image: ReplayFrameImage
                if let previous, previous.frame == frame {
                    image = previous.image
                } else {
                    guard let rendered = render(frame, script: script, speed: timeline.speed, content: content) else {
                        throw ReplayVideoEncoder.Failure.cannotAppend
                    }
                    image = rendered
                }
                try await pending?.value
                pending = Task { try await encoder.append(image, at: index) }
                previous = (frame, image)
                progress(Double(index + 1) / Double(timeline.frameCount + 1))
            }
            try await pending?.value
            try Task.checkCancellation()
            try await encoder.finish(frameCount: timeline.frameCount)
            progress(1)
        } catch {
            await encoder.cancel()
            throw error
        }
        return ReplayVideo(url: url, duration: Double(timeline.frameCount) / Double(ReplayTimeline.framesPerSecond))
    }

    /// 1 コマを描く
    static func render(_ frame: ReplayFrame, script: ReplayScript, speed: Double, content: TributeStatementContent) -> ReplayFrameImage? {
        autoreleasepool {
            let renderer = ImageRenderer(content: ReplayVideoFrame(script: script, frame: frame, speed: speed, content: content))
            renderer.proposedSize = ProposedViewSize(ReplayVideoFrame.format.canvasSize)
            renderer.scale = ReplayVideoFrame.format.scale
            renderer.isOpaque = true
            return renderer.cgImage.map(ReplayFrameImage.init)
        }
    }
}

/// 共有のプレビューで、リプレイ動画を作って持っておく係。
///
/// 動画はアプリの一時フォルダ（`ReplayVideoFiles`）に置き、共有のプレビューを閉じたとき・作り直すとき・中止したときに消す
/// （docs/SPEC.md「動画は共有後に削除する」。`ShareLink` は共有シートを閉じたことを知らせないので、プレビューを閉じたときにする）。
/// 起動のときにも、前の残りを消す
@MainActor
@Observable
final class ShareVideoExport {
    enum State: Equatable {
        /// まだ作っていない（中止したときも）
        case idle
        /// 作っている（0〜1）
        case exporting(Double)
        case ready(ReplayVideo)
        case failed
    }

    private(set) var state = State.idle
    /// 今の動画（作っている途中を含む）を、どの中身で作ったか。中身（端末の表示）が変わったら作り直す
    private(set) var key: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var fileURL: URL?
    /// 作り直したときに、前の書き出しの知らせを受け取らないための番号
    @ObservationIgnored private var generation = 0

    var isExporting: Bool {
        if case .exporting = state {
            return true
        }
        return false
    }

    var video: ReplayVideo? {
        if case let .ready(video) = state {
            return video
        }
        return nil
    }

    func start(script: ReplayScript, content: TributeStatementContent, key: String) {
        discard()
        generation += 1
        let generation = generation
        let url: URL
        do {
            url = try ReplayVideoFiles.makeURL()
        } catch {
            state = .failed
            return
        }
        fileURL = url
        self.key = key
        state = .exporting(0)
        task = Task { [weak self] in
            do {
                let video = try await ReplayVideoMaker.make(script: script, content: content, to: url) { value in
                    guard let self, self.generation == generation else {
                        return
                    }
                    self.state = .exporting(value)
                }
                guard let self, self.generation == generation, !Task.isCancelled else {
                    ReplayVideoFiles.remove(url)
                    return
                }
                self.state = .ready(video)
            } catch {
                ReplayVideoFiles.remove(url)
                guard let self, self.generation == generation, !Task.isCancelled else {
                    return
                }
                self.state = .failed
            }
        }
    }

    /// 作るのを止めるか、作った動画を消す
    func discard() {
        generation += 1
        task?.cancel()
        task = nil
        if let fileURL {
            ReplayVideoFiles.remove(fileURL)
        }
        fileURL = nil
        key = nil
        state = .idle
    }

    /// 作っている途中なら止める（バックグラウンドに移ったとき）。できあがった動画は残す
    func cancelExport() {
        guard isExporting else {
            return
        }
        discard()
    }
}

/// リプレイ動画の一時ファイル。アプリの一時フォルダの `ReplayVideos/<UUID>/UncleRAM-replay.mp4` に置く
nonisolated enum ReplayVideoFiles {
    static let fileName = "UncleRAM-replay.mp4"

    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ReplayVideos", isDirectory: true)
    }

    /// 新しい動画の置き場所。共有したときのファイル名をそろえるため、動画ごとにフォルダを分ける
    static func makeURL() throws -> URL {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    /// 動画を、フォルダごと消す
    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// 前に作った動画の残りをすべて消す（起動のとき）
    static func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// 共有シートと、Mac の「動画を保存」に渡す動画
nonisolated struct ShareVideoFile: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mpeg4Movie) { file in
            SentTransferredFile(file.url)
        }
        .suggestedFileName(ReplayVideoFiles.fileName)
    }
}

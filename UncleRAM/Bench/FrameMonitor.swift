import Foundation
import QuartzCore
#if os(macOS)
import AppKit
#endif

/// 画面の更新の間隔を見て、落ちたフレームを数える（試作の合格条件「最高速でも 60fps を保つ」の計測用）。
///
/// 前のフレームからの間隔が、予定の間隔の 1.5 倍を越えたら、越えた分を落ちたフレームとして数える。
@MainActor
final class FrameMonitor: NSObject {
    struct Stats: Codable, Equatable {
        var frames = 0
        var droppedFrames = 0
        var worstIntervalMilliseconds = 0.0
        /// 数えた間の秒数。60fps 未満の一定の速さ（50Hz など）は落ちたフレームに表れないので、平均の速さも見る
        var seconds = 0.0

        /// 平均の更新の速さ（回 / 秒）
        var averageFramesPerSecond: Double {
            seconds > 0 ? Double(frames) / seconds : 0
        }

        var droppedRatio: Double {
            frames + droppedFrames > 0 ? Double(droppedFrames) / Double(frames + droppedFrames) : 0
        }
    }

    /// 献上中のフレーム
    private(set) var stats = Stats()
    /// 離してから結果が出るまで（確保を止めて、全メモリを解放している間）のフレーム
    private(set) var releaseStats = Stats()
    private var releasing = false
    private var lastTimestamp: CFTimeInterval?
    private var link: CADisplayLink?

    func start() {
        stop()
        stats = Stats()
        releaseStats = Stats()
        releasing = false
        lastTimestamp = nil
        #if os(iOS)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
        #elseif os(macOS)
        guard let screen = NSScreen.main else {
            return
        }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        self.link = link
        #endif
    }

    /// ここから先のフレームを、解放の間として数える
    func markRelease() {
        releasing = true
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let lastTimestamp else {
            return
        }
        let expected = 1.0 / 60
        let interval = link.timestamp - lastTimestamp
        var target = releasing ? releaseStats : stats
        target.frames += 1
        target.seconds += interval
        target.worstIntervalMilliseconds = max(target.worstIntervalMilliseconds, interval * 1000)
        if interval > expected * 1.5 {
            target.droppedFrames += Int((interval / expected).rounded()) - 1
        }
        if releasing {
            releaseStats = target
        } else {
            stats = target
        }
    }
}

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

        var droppedRatio: Double {
            frames + droppedFrames > 0 ? Double(droppedFrames) / Double(frames + droppedFrames) : 0
        }
    }

    private(set) var stats = Stats()
    private var lastTimestamp: CFTimeInterval?
    #if os(iOS)
    private var link: CADisplayLink?
    #elseif os(macOS)
    private var link: CADisplayLink?
    #endif

    func start() {
        stop()
        stats = Stats()
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
        stats.frames += 1
        stats.worstIntervalMilliseconds = max(stats.worstIntervalMilliseconds, interval * 1000)
        if interval > expected * 1.5 {
            stats.droppedFrames += Int((interval / expected).rounded()) - 1
        }
    }
}

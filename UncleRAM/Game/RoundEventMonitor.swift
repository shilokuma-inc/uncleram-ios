import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// ラウンドを止める OS のできごとを、`RoundEngine` に伝える。docs/SPEC.md「ラウンドの状態と中断」「Mac 版の技術仕様」。
///
/// - 発熱が serious 以上 → 無効
/// - メモリ警告（iOS）・メモリの逼迫（iOS は監査、Mac は warning で安全ラインと同じく納品）
/// - Mac: スペースキーの長押し、ウィンドウが前面でなくなったら離したとみなす、0.5 秒ごとに圧縮量を見て急に増えたら監査
@MainActor
final class RoundEventMonitor {
    /// Mac で、0.5 秒の間に圧縮メモリがこれだけ増えたら「監査」にする（枠に対する割合と下限）。仮の値で、試作の計測で決める
    static let compressionSurgeRatio = 0.05
    static let compressionSurgeMinimumBytes: UInt64 = 256 * 1024 * 1024
    static let compressionCheckInterval: TimeInterval = 0.5

    private let engine: RoundEngine
    private var observers: [NSObjectProtocol] = []
    private var pressureSource: (any DispatchSourceMemoryPressure)?
    #if os(macOS)
    private var keyMonitor: Any?
    private var compressionTask: Task<Void, Never>?
    #endif

    init(engine: RoundEngine) {
        self.engine = engine
    }

    func start() {
        guard observers.isEmpty else {
            return
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.thermalStateChanged()
            }
        })
        #if os(iOS)
        observers.append(center.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.engine.memoryWarning()
            }
        })
        #elseif os(macOS)
        for name in [NSWindow.didResignKeyNotification, NSApplication.didResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.engine.endHold(.windowResigned)
                }
            })
        }
        startKeyMonitor()
        startCompressionWatch()
        #endif

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.memoryPressure()
            }
        }
        source.resume()
        pressureSource = source
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        pressureSource?.cancel()
        pressureSource = nil
        #if os(macOS)
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        compressionTask?.cancel()
        compressionTask = nil
        #endif
    }

    private func thermalStateChanged() {
        if ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
            engine.void(.thermal)
        } else {
            engine.refreshBudget()
        }
    }

    private func memoryPressure() {
        #if os(macOS)
        engine.memoryPressureWarning()
        #else
        engine.memoryWarning()
        #endif
    }

    #if os(macOS)
    /// スペースキーの長押しで献上する（キーの繰り返しは無視する）
    private func startKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard event.keyCode == 49, event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask) else {
                return event
            }
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                if event.type == .keyDown {
                    if !event.isARepeat {
                        self.engine.beginHold()
                    }
                } else {
                    self.engine.endHold(.released)
                }
            }
            return nil
        }
    }

    /// 0.5 秒ごとに圧縮メモリの量を見て、急に増えたら監査にする（Mac 全体が遅くなる手前で止めるため）
    private func startCompressionWatch() {
        compressionTask = Task { [weak self] in
            var previous: UInt64?
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.compressionCheckInterval))
                guard let self else {
                    return
                }
                guard self.engine.phase == .donating, let compressed = HostMemory.statistics()?.compressedBytes else {
                    previous = nil
                    continue
                }
                defer { previous = compressed }
                guard let previous, compressed > previous else {
                    continue
                }
                let threshold = max(
                    UInt64(Double(self.engine.budgetBytes) * Self.compressionSurgeRatio),
                    Self.compressionSurgeMinimumBytes
                )
                if compressed - previous >= threshold {
                    self.engine.memoryWarning()
                }
            }
        }
    }
    #endif
}

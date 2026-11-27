import Foundation
import StoreKit

/// 画面の「計測」ボタンの出し方（2026-11-28 にユーザーが決定、#51）。
///
/// TestFlight の外部テストの人に開発用のボタンを見せないよう、既定は隠す。
/// 設定のバージョン表記を続けて 5 回タップすると、表示を切り替えられる（端末に記録する。`LocalStore.showsBenchButton`）。
/// 切り替えられるのは Debug ビルドと App Store 以外の配布（TestFlight・Xcode から入れた Release）だけで、App Store 版では何も起きない。
/// 起動引数 `-bench <ラウンド数>` で計測したときは、設定に関係なくボタンを出す
enum BenchAccess {
    /// 表示を切り替えるのに要る、続けてのタップの回数
    static let requiredTaps = 5
    /// タップの間がこれより空いたら数え直す（秒）
    static let maxTapInterval: TimeInterval = 2

    /// 計測のボタンを切り替えられる環境か（Debug ビルドと、App Store 以外の配布）
    static func isSwitchable() async -> Bool {
        #if DEBUG
        return true
        #else
        let environment = try? await AppTransaction.shared.payloadValue.environment
        return environment != nil && environment != .production
        #endif
    }

    /// 画面に「計測」ボタンを出すか
    /// - Parameters:
    ///   - isSwitchable: 切り替えられる環境か（`isSwitchable()`）
    ///   - isEnabled: 端末に記録した設定（`LocalStore.showsBenchButton`）
    ///   - isLaunchedForBench: 起動引数で計測したか
    static func showsButton(isSwitchable: Bool, isEnabled: Bool, isLaunchedForBench: Bool) -> Bool {
        isLaunchedForBench || (isSwitchable && isEnabled)
    }
}

/// 続けてのタップを数える。間が `maxInterval` より空いたら、1 回目から数え直す
struct RepeatedTapCounter {
    let requiredTaps: Int
    let maxInterval: TimeInterval
    /// 今、続けて何回タップしたか
    private(set) var taps = 0
    private var lastTap: Date?

    init(requiredTaps: Int = BenchAccess.requiredTaps, maxInterval: TimeInterval = BenchAccess.maxTapInterval) {
        self.requiredTaps = requiredTaps
        self.maxInterval = maxInterval
    }

    /// タップを 1 回数える。続けて `requiredTaps` 回に届いたら true を返し、数え直す
    mutating func register(at date: Date = .now) -> Bool {
        if let lastTap, date.timeIntervalSince(lastTap) <= maxInterval {
            taps += 1
        } else {
            taps = 1
        }
        lastTap = date
        guard taps >= requiredTaps else {
            return false
        }
        taps = 0
        lastTap = nil
        return true
    }
}

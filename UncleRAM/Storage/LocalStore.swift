import Foundation
import Observation

/// 端末の中だけに残す値。iCloud には入れない（docs/SPEC.md「初回起動と設定」）。
/// 進み具合のうち端末をまたいで共有するもの（クレジット・称号など）は、iCloud 同期と一緒に段取り 4 で別に持つ
@Observable
final class LocalStore {
    private enum Key {
        static let hasAcknowledgedSafetyNotice = "hasAcknowledgedSafetyNotice"
        static let tapToDonate = "tapToDonate"
        static let all = [hasAcknowledgedSafetyNotice, tapToDonate]
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// 初回の案内（本物のメモリを使うこと・裏のアプリが終了することがあること・端末が速くなるアプリではないこと）を閉じたか
    var hasAcknowledgedSafetyNotice: Bool {
        didSet { defaults.set(hasAcknowledgedSafetyNotice, forKey: Key.hasAcknowledgedSafetyNotice) }
    }

    /// 設定「タップで献上」。長押しの代わりに、1 回目のタップで献上を始め、もう一度タップすると納品する
    /// （Mac はクリックかスペースキーを 2 回。docs/SPEC.md「アクセシビリティ」）。ランキングは長押しと区別しない
    var tapToDonate: Bool {
        didSet { defaults.set(tapToDonate, forKey: Key.tapToDonate) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasAcknowledgedSafetyNotice = defaults.bool(forKey: Key.hasAcknowledgedSafetyNotice)
        tapToDonate = defaults.bool(forKey: Key.tapToDonate)
    }

    /// 設定「データの初期化」。端末の中の記録と設定をすべて消す（2026-11-26 にユーザーが決定）。
    /// Game Center に送った記録は消えない。値を足したら `Key.all` にも足す
    func resetAll() {
        for key in Key.all {
            defaults.removeObject(forKey: key)
        }
        hasAcknowledgedSafetyNotice = false
        tapToDonate = false
    }
}

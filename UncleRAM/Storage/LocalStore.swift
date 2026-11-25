import Foundation
import Observation

/// 端末の中だけに残す値。iCloud には入れない（docs/SPEC.md「初回起動と設定」）。
/// 進み具合のうち端末をまたいで共有するもの（クレジット・称号など）は、iCloud 同期と一緒に段取り 4 で別に持つ
@Observable
final class LocalStore {
    private enum Key {
        static let hasAcknowledgedSafetyNotice = "hasAcknowledgedSafetyNotice"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// 初回の案内（本物のメモリを使うこと・裏のアプリが終了することがあること・端末が速くなるアプリではないこと）を閉じたか
    var hasAcknowledgedSafetyNotice: Bool {
        didSet { defaults.set(hasAcknowledgedSafetyNotice, forKey: Key.hasAcknowledgedSafetyNotice) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasAcknowledgedSafetyNotice = defaults.bool(forKey: Key.hasAcknowledgedSafetyNotice)
    }
}

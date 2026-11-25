import Foundation

/// 送り直しの待ち行列と、自分の最高記録の保存先。
///
/// あとで保存の仕組み（データの初期化を含む #29）に寄せられるよう、読み書きの 2 つだけにしておく。テストでは偽物に差し替える。
protocol RankingStore: AnyObject {
    var pendingScores: PendingScoreQueue { get set }
    var personalBests: PersonalBests { get set }
}

/// UserDefaults に JSON で置く（端末の中だけ。iCloud には入れない）
final class UserDefaultsRankingStore: RankingStore {
    /// 中身の形を変えるときは、キーの版を上げる（読めない古い値は空として扱う）
    static let pendingScoresKey = "leaderboards.pendingScores.v1"
    static let personalBestsKey = "leaderboards.personalBests.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var pendingScores: PendingScoreQueue {
        get {
            load(PendingScoreQueue.self, forKey: Self.pendingScoresKey) ?? PendingScoreQueue()
        }
        set {
            save(newValue, forKey: Self.pendingScoresKey)
        }
    }

    var personalBests: PersonalBests {
        get {
            load(PersonalBests.self, forKey: Self.personalBestsKey) ?? PersonalBests()
        }
        set {
            save(newValue, forKey: Self.personalBestsKey)
        }
    }

    private func load<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save(_ value: some Encodable, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}

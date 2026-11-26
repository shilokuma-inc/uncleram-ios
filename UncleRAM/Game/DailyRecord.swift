import Foundation

/// ラウンドの種類。速達便か、その日のデイリーか
nonisolated enum RoundMode: Sendable, Equatable {
    case express
    case daily(DailyChallenge)

    var daily: DailyChallenge? {
        if case let .daily(challenge) = self {
            return challenge
        }
        return nil
    }
}

/// デイリーの 1 日 1 回の記録。押し始めた時点で、その日の 1 回を使う（2026-11-26 にユーザーが決定）。
///
/// 無効（裏に回った・発熱）を数えないと、「始めてヒントを見てから裏に回して無効にし、もう一度挑戦する」ことで、
/// その日の回収ライン（全員同じ）が分かってしまう。なので、無効になってもその日はやり直せない
nonisolated struct DailyRecord: Sendable, Equatable, Codable {
    enum Result: String, Sendable, Codable {
        /// 押し始めたが、結果がまだ無い（途中でアプリが終わった、など）
        case started
        case delivered
        case collected
        /// 監査（納品扱い）
        case audited
        case voided
    }

    /// 挑戦した日（世界標準時）。`DailyDay.daysSince1970`
    let day: Int
    var result: Result
    /// 献上量のスコア（納品・監査のとき）
    var score: Int?

    static func started(on day: DailyDay) -> DailyRecord {
        DailyRecord(day: day.daysSince1970, result: .started, score: nil)
    }

    /// 結果を書き込んだ記録
    func finished(with outcome: RoundOutcome) -> DailyRecord {
        var record = self
        switch outcome.kind {
        case .delivered:
            record.result = .delivered
            record.score = outcome.score
        case .audited:
            record.result = .audited
            record.score = outcome.score
        case .collected:
            record.result = .collected
            record.score = 0
        case .voided:
            record.result = .voided
            record.score = nil
        }
        return record
    }

    /// day に、もう挑戦したか
    func isPlayed(on day: DailyDay) -> Bool {
        self.day == day.daysSince1970
    }
}

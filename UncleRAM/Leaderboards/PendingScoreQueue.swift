import Foundation

/// 送れなかったスコアの待ち行列（docs/SPEC.md「初回起動と設定」: 送れなかったスコアは端末に貯めて送り直す。デイリーはその日のうちだけ）。
///
/// サインイン前の記録は、ここに入れない（`RankingSubmitter` が入れない）。
nonisolated struct PendingScoreQueue: Sendable, Equatable, Codable {
    private(set) var scores: [LeaderboardScore] = []

    var isEmpty: Bool {
        scores.isEmpty
    }

    /// 貯める。どのランキングも「いちばん良いスコアを残す」ので、同じランキングの同じ回には大きい方だけを残す
    /// （低い方を送っても順位は変わらない。1 本の回に 1 つしか残らないので、待ち行列は長く伸びない）
    mutating func enqueue(_ score: LeaderboardScore) {
        guard let index = scores.firstIndex(where: { Self.isSameRound($0, score) }) else {
            scores.append(score)
            return
        }
        if score.value > scores[index].value {
            scores[index] = score
        }
    }

    /// 送れたスコアと、それで要らなくなった同じランキングの同じ回の低いスコアを外す
    mutating func markSent(_ score: LeaderboardScore) {
        scores.removeAll { Self.isSameRound($0, score) && $0.value <= score.value }
    }

    /// 送る回がもう無いランキングの回（挑戦した日の回が閉じたデイリー）のスコアを、すべて捨てる
    mutating func discardRound(of score: LeaderboardScore) {
        scores.removeAll { Self.isSameRound($0, score) }
    }

    /// 期限を過ぎたデイリーを捨てる
    mutating func removeExpired(at now: Date) {
        scores.removeAll { $0.isExpired(at: now) }
    }

    /// 同じランキングの同じ回か（デイリーは期限が同じ日なら同じ回）
    private static func isSameRound(_ lhs: LeaderboardScore, _ rhs: LeaderboardScore) -> Bool {
        lhs.leaderboardID == rhs.leaderboardID && lhs.expiresAt == rhs.expiresAt
    }
}

import Foundation

/// 1 本のランキングに送る値。送れなかったときは、そのまま待ち行列に貯める
nonisolated struct LeaderboardScore: Sendable, Equatable, Codable {
    let leaderboardID: String
    let value: Int
    /// `LeaderboardContext` で符号化した、端末の種類とメモリのクラス
    let context: Int
    /// これを過ぎたら送らない。デイリーは挑戦した日の世界標準時 24 時（その日の回の終わり）。速達便は nil
    let expiresAt: Date?

    func isExpired(at now: Date) -> Bool {
        guard let expiresAt else {
            return false
        }
        return now >= expiresAt
    }

    /// デイリーで、繰り返し型ランキングの回の終わりが、このスコアの期限（挑戦した日の 24 時）と同じか。
    /// 違えば、読み込んでいる間に日付が変わったなどで、挑戦した日の回ではない。1 秒未満のずれは、時刻の端数とみなして同じにする
    func belongs(toOccurrenceEndingAt endDate: Date?) -> Bool {
        guard let expiresAt, let endDate else {
            return false
        }
        return abs(endDate.timeIntervalSince(expiresAt)) < 1
    }
}

/// ランキングに入るラウンド。デイリーは、挑戦した日（ラウンドの条件を作った日）を持つ
nonisolated enum RankedRound: Sendable, Equatable {
    case express
    case daily(DailyDay)

    var mode: RankingMode {
        switch self {
        case .express:
            .express
        case .daily:
            .daily
        }
    }

    /// 送る期限。デイリーは挑戦した日の世界標準時 24 時（繰り返し型ランキングの、その日の回の終わり）。速達便は無し
    var expiresAt: Date? {
        switch self {
        case .express:
            nil
        case .daily(let day):
            DailyDay(daysSince1970: day.daysSince1970 + 1).start
        }
    }
}

/// ランキングに送る 1 ラウンドの記録。`RankingRecord.decide` で、送るものだけを作る
nonisolated struct RankingRecord: Sendable, Equatable {
    /// 腕前スコアの上限（gameCenterResources.json の腕前のランキングの scoreRangeEnd と同じ）
    static let maximumSkillScore = 300

    let round: RankedRound
    /// 腕前スコア（pt）
    let skillScore: Int
    /// 献上量のスコア（献上量 MB × ニアミス倍率）
    let donatedScore: Int
    let device: DeviceMemoryProfile

    var mode: RankingMode {
        round.mode
    }

    /// 送る期限。デイリーは挑戦した日の世界標準時 24 時、速達便は無し
    var expiresAt: Date? {
        round.expiresAt
    }

    /// 送る 2 本（腕前と、自分のクラスの献上量）
    var leaderboardScores: [LeaderboardScore] {
        let context = LeaderboardContext.encode(device)
        let skill = Leaderboard(mode: mode, kind: .skill)
        let donated = Leaderboard(mode: mode, kind: .donated(device.memoryClass))
        return [
            LeaderboardScore(leaderboardID: skill.identifier, value: skillScore, context: context, expiresAt: expiresAt),
            LeaderboardScore(leaderboardID: donated.identifier, value: donatedScore, context: context, expiresAt: expiresAt)
        ]
    }
}

/// ランキングに送るかどうか
nonisolated enum RankingDecision: Sendable, Equatable {
    case submit(RankingRecord)
    case skip(RankingSkipReason)
}

/// 練習（ランキングに送らないラウンド）の種類
nonisolated enum RankingPractice: Sendable, Equatable {
    /// 最初の 1 回の練習ラウンド（回収ラインを枠の 50% に固定する）
    case firstRound
    /// 過去の日のデイリー（/d/<日付> から開いた練習）
    case pastDaily
}

/// ランキングに送らない理由
nonisolated enum RankingSkipReason: Sendable, Equatable {
    /// 練習ラウンドと、過去の日のデイリー
    case practice(RankingPractice)
    /// 無効になったラウンド（バックグラウンドへの移行・発熱）。スコアが無いので送らない
    case voided
    /// 世界標準時 0 時をまたいで終わったデイリー。挑戦した日の回は閉じているので送らない
    case dailyClosed
    /// 腕前スコアが 0〜300 pt の外
    case skillScoreOutOfRange
    /// 献上量（倍率をかける前）が、端末の搭載メモリ（正式な容量に丸めた値）を超えている
    case donatedOverMemory
}

extension RankingRecord {
    /// ラウンドの結果から、ランキングに送るかを決める（docs/SPEC.md「ランキング」の「不正なスコア」、「初回起動と設定」）。
    ///
    /// 定期便は `RankedRound` に無いので、渡すことができない。回収されたラウンドは 0 を送る（ランキングに参加した記録になる）。
    /// - Parameters:
    ///   - round: 速達便か、デイリー（挑戦した日つき）か
    ///   - practice: 練習なら、その種類。今日（世界標準時）のデイリーかどうかは、デイリーの日付を決める側で判定して渡す
    ///   - device: 端末の種類と搭載メモリ。ふつうは `DeviceMemoryProfile.current`
    ///   - endedAt: ラウンドが終わった時刻。デイリーで、挑戦した日の世界標準時 24 時を過ぎていたら送らない
    static func decide(
        outcome: RoundOutcome,
        round: RankedRound,
        practice: RankingPractice?,
        device: DeviceMemoryProfile,
        endedAt: Date
    ) -> RankingDecision {
        if let practice {
            return .skip(.practice(practice))
        }
        if case .voided = outcome.kind {
            return .skip(.voided)
        }
        if let expiresAt = round.expiresAt, endedAt >= expiresAt {
            return .skip(.dailyClosed)
        }
        // 腕前スコアの丸め方は RoundOutcome.skillScore（到達率 × 倍率を最後に 1 回だけ四捨五入する）
        let skillScore = outcome.skillScore
        if let reason = implausibility(skillScore: skillScore, donatedBytes: outcome.donatedBytes, device: device) {
            return .skip(reason)
        }
        return .submit(
            RankingRecord(
                round: round,
                skillScore: skillScore,
                donatedScore: outcome.score,
                device: device
            )
        )
    }

    /// あり得ない値か。腕前スコアは 0〜300 pt、献上量は端末の搭載メモリまで（docs/SPEC.md「ランキング」の「不正なスコア」）
    static func implausibility(skillScore: Int, donatedBytes: UInt64, device: DeviceMemoryProfile) -> RankingSkipReason? {
        guard (0...maximumSkillScore).contains(skillScore) else {
            return .skillScoreOutOfRange
        }
        guard donatedBytes <= device.memoryBytes else {
            return .donatedOverMemory
        }
        return nil
    }
}

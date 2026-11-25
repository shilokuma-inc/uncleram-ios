import Foundation

/// 自分の最高記録。サインインしていない人にも、ランキングの画面で見せる（docs/SPEC.md「Game Center と名前の扱い」）。
///
/// 端末の中だけに残し、iCloud には入れない。ランキングに送れる記録（`RankingRecord`）だけを数える。
nonisolated struct PersonalBests: Sendable, Equatable, Codable {
    struct Best: Sendable, Equatable, Codable {
        /// 腕前スコアの最高（pt）
        var skillScore: Int
        /// 献上量のスコアの最高（献上量 MB × ニアミス倍率）
        var donatedScore: Int
        /// 献上量の最高を出したクラス。献上量はクラスの中でだけ比べる
        var memoryClass: MemoryClass
        /// デイリーの記録の期限（遊んだ日の世界標準時 24 時）。速達便は nil
        var expiresAt: Date?
    }

    /// 速達便のこれまでの最高
    private(set) var express: Best?
    /// デイリーの最高。期限を過ぎたものは `daily(at:)` で見せない
    private var latestDaily: Best?

    /// 今日のデイリーの最高
    func daily(at now: Date) -> Best? {
        guard let latestDaily, let expiresAt = latestDaily.expiresAt, now < expiresAt else {
            return nil
        }
        return latestDaily
    }

    mutating func record(_ record: RankingRecord) {
        switch record.mode {
        case .express:
            express = Self.merged(express, with: record)
        case .daily:
            // 前の日の記録とは比べない
            let current = latestDaily?.expiresAt == record.expiresAt ? latestDaily : nil
            latestDaily = Self.merged(current, with: record)
        }
    }

    /// 腕前と献上量は、ランキングと同じく別々に最高を残す
    private static func merged(_ best: Best?, with record: RankingRecord) -> Best {
        let memoryClass = record.device.memoryClass
        guard var best else {
            return Best(
                skillScore: record.skillScore,
                donatedScore: record.donatedScore,
                memoryClass: memoryClass,
                expiresAt: record.expiresAt
            )
        }
        best.skillScore = max(best.skillScore, record.skillScore)
        // バックアップから別の端末に移ってクラスが変わったら、献上量は新しいクラスで数え直す
        if best.memoryClass == memoryClass {
            best.donatedScore = max(best.donatedScore, record.donatedScore)
        } else {
            best.donatedScore = record.donatedScore
            best.memoryClass = memoryClass
        }
        return best
    }
}

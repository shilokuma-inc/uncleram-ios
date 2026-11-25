import Foundation
import os

/// ラウンドの記録をランキングに送り、送れなかった分を貯めて送り直す（docs/SPEC.md「初回起動と設定」）。
///
/// ラウンドの終わりに `submit(_:)`、サインインできたときとアプリが前面に戻ったときに `resendPending()` を呼ぶ。
/// このつなぎ込みは、ランキングの画面と一緒に別の PR で行う。
final class RankingSubmitter {
    private let service: any LeaderboardService
    private let store: any RankingStore
    private let now: () -> Date
    private let logger = Logger(subsystem: "jp.shilokuma.UncleRAM", category: "Leaderboards")
    /// 送り直しを重ねて走らせない
    private var isResending = false

    init(
        service: any LeaderboardService = GameKitLeaderboardService(),
        store: any RankingStore = UserDefaultsRankingStore(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.service = service
        self.store = store
        self.now = now
    }

    /// 自分の最高記録（端末の中だけ）
    var personalBests: PersonalBests {
        store.personalBests
    }

    /// 送れずに貯まっているスコア
    var pendingScores: PendingScoreQueue {
        store.pendingScores
    }

    /// 1 ラウンドの記録を、自分の最高記録に残してからランキングに送る。送れなかった分は貯める。
    ///
    /// サインインしていないときは送らず、貯めもしない（サインイン前の記録は送らない）
    func submit(_ record: RankingRecord) async {
        store.personalBests.record(record)
        guard service.isAuthenticated else {
            return
        }
        for score in record.leaderboardScores {
            await send(score, enqueueOnFailure: true)
        }
    }

    /// 貯まっているスコアを送り直す。期限を過ぎたデイリーは捨てる
    func resendPending() async {
        guard service.isAuthenticated, !isResending else {
            return
        }
        isResending = true
        defer {
            isResending = false
        }
        store.pendingScores.removeExpired(at: now())
        // 送っている間に新しいスコアが貯まることがあるので、待ち行列は 1 本ずつ読み直して書く
        for score in store.pendingScores.scores {
            await send(score, enqueueOnFailure: false)
        }
        store.pendingScores.removeExpired(at: now())
    }

    private func send(_ score: LeaderboardScore, enqueueOnFailure: Bool) async {
        guard !score.isExpired(at: now()) else {
            return
        }
        do {
            try await service.submit(score)
            store.pendingScores.markSent(score)
        } catch {
            logger.notice("Could not submit to \(score.leaderboardID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if enqueueOnFailure {
                store.pendingScores.enqueue(score)
            }
        }
    }
}

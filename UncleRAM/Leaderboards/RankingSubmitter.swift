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

    private enum Delivery {
        case sent
        /// 挑戦した日の回が、もう開いていない
        case roundClosed
    }

    private func send(_ score: LeaderboardScore, enqueueOnFailure: Bool) async {
        guard !score.isExpired(at: now()) else {
            return
        }
        do {
            switch try await deliver(score) {
            case .sent:
                store.pendingScores.markSent(score)
            case .roundClosed:
                logger.notice("Discarded a daily score for a closed round of \(score.leaderboardID, privacy: .public)")
                store.pendingScores.discardRound(of: score)
            }
        } catch {
            logger.notice("Could not submit to \(score.leaderboardID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if enqueueOnFailure {
                store.pendingScores.enqueue(score)
            }
        }
    }

    /// 速達便は、受け取った時点の回に送る（回は 1 つだけ）。
    /// デイリーは、受け取った時点の回に送ると、通信が世界標準時 0 時をまたいだときに次の日の回へ入ってしまう。
    /// そこで今の回を読み込み、その回の終わりが挑戦した日の 24 時と同じときだけ、その回に送る
    private func deliver(_ score: LeaderboardScore) async throws -> Delivery {
        guard score.expiresAt != nil else {
            try await service.submit(score)
            return .sent
        }
        guard let occurrence = try await service.loadCurrentOccurrence(of: score.leaderboardID),
              score.belongs(toOccurrenceEndingAt: occurrence.endDate) else {
            return .roundClosed
        }
        try await occurrence.submit(score)
        return .sent
    }
}

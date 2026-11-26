import Foundation
import Observation

/// ランキングのつなぎ込み。ラウンドの結果を送り、Game Center のサインインと送り直しを受け持つ（docs/SPEC.md「初回起動と設定」）。
/// AppRoot が 1 つ作り、画面に environment で渡す
@Observable
final class RankingCenter {
    let signIn: GameCenterSignIn
    @ObservationIgnored let submitter: RankingSubmitter
    @ObservationIgnored private let device: () -> DeviceMemoryProfile
    @ObservationIgnored private let now: () -> Date
    /// 自分の最高記録が変わったら、ランキングの画面を描き直す
    private(set) var personalBests: PersonalBests

    init(
        signIn: GameCenterSignIn = GameCenterSignIn(),
        submitter: RankingSubmitter = RankingSubmitter(),
        device: @escaping () -> DeviceMemoryProfile = { .current },
        now: @escaping () -> Date = { Date() }
    ) {
        self.signIn = signIn
        self.submitter = submitter
        self.device = device
        self.now = now
        personalBests = submitter.personalBests
        signIn.onSignedIn = { [weak self] in
            self?.resendPending()
        }
    }

    /// 起動引数 `-disableGameCenter YES` で、Game Center のサインインを始めない（UI テストで、サインインの画面に流れを止められないように）
    static let isDisabledByLaunchArguments = UserDefaults.standard.bool(forKey: "disableGameCenter")

    /// サインインを始める。最初のラウンドが終わってから呼ぶ（それより前は、遊ぶ前にサインインの画面が出てしまうため）
    func startSignIn() {
        guard !Self.isDisabledByLaunchArguments else {
            return
        }
        signIn.start()
    }

    /// ラウンドの結果をランキングに送る。練習ラウンド・過去の日のデイリー・無効・あり得ない値は送らない（`RankingRecord.decide`）
    func record(_ outcome: RoundOutcome, mode: RoundMode) {
        guard case let .submit(record) = decision(for: outcome, mode: mode) else {
            return
        }
        Task {
            await submitter.submit(record)
            personalBests = submitter.personalBests
        }
    }

    /// 送るかどうか。速達便はいつも、デイリーは今日（世界標準時）の分だけ送る
    func decision(for outcome: RoundOutcome, mode: RoundMode) -> RankingDecision {
        let round: RankedRound
        var practice: RankingPractice? = outcome.plan.isPractice ? .firstRound : nil
        switch mode {
        case .express:
            round = .express
        case let .daily(challenge):
            round = .daily(challenge.day)
            if challenge.status(now: now()) != .today {
                practice = practice ?? .pastDaily
            }
        }
        return RankingRecord.decide(outcome: outcome, round: round, practice: practice, device: device(), endedAt: now())
    }

    /// 送れずに貯まっているスコアを送り直す（サインインできたとき・アプリが前面に戻ったとき）
    func resendPending() {
        Task {
            await submitter.resendPending()
        }
    }
}

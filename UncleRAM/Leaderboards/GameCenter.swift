import GameKit
import Observation
import os
#if os(macOS)
import AppKit

/// GameKit が渡すサインインの画面の型
typealias GameCenterViewController = NSViewController
#else
import UIKit

/// GameKit が渡すサインインの画面の型
typealias GameCenterViewController = UIViewController
#endif

/// ランキングへの送信。テストでは偽物に差し替えて、実際の Game Center には触れない
protocol LeaderboardService: AnyObject {
    /// Game Center にサインインしているか
    var isAuthenticated: Bool { get }
    /// 1 本のランキングの、Game Center が受け取った時点の回に送る（速達便。繰り返し型ではないので回は 1 つだけ）
    func submit(_ score: LeaderboardScore) async throws
    /// 繰り返し型のランキング（デイリー）の、今の回を読み込む。回が無いときは nil
    func loadCurrentOccurrence(of leaderboardID: String) async throws -> (any LeaderboardOccurrence)?
}

/// 繰り返し型のランキングの 1 回分
protocol LeaderboardOccurrence: AnyObject {
    /// 回の終わり（startDate + duration）。分からないときは nil
    var endDate: Date? { get }
    /// この回にだけ送る。回が終わっていたら失敗し、次の回には入らない
    func submit(_ score: LeaderboardScore) async throws
}

/// GameKit で送る薄い層。
///
/// Mac には今は Game Center の権限が無い（docs/SPEC.md「Game Center と名前の扱い」）。権限が無くてもビルドは通り、
/// サインインが失敗して `isAuthenticated` が false のままになるので、何も送らない。
final class GameKitLeaderboardService: LeaderboardService {
    var isAuthenticated: Bool {
        GKLocalPlayer.local.isAuthenticated
    }

    func submit(_ score: LeaderboardScore) async throws {
        try await GKLeaderboard.submitScore(
            score.value,
            context: score.context,
            player: GKLocalPlayer.local,
            leaderboardIDs: [score.leaderboardID]
        )
    }

    func loadCurrentOccurrence(of leaderboardID: String) async throws -> (any LeaderboardOccurrence)? {
        let leaderboards = try await GKLeaderboard.loadLeaderboards(IDs: [leaderboardID])
        return leaderboards.first.map { GameKitLeaderboardOccurrence(leaderboard: $0) }
    }
}

/// GameKit の繰り返し型ランキングの 1 回分。
///
/// クラスメソッドの `GKLeaderboard.submitScore(_:context:player:leaderboardIDs:)` は、Game Center が受け取った時点の回に入る。
/// インスタンスメソッドの `submitScore(_:context:player:)` は、読み込んだ回がまだ開いているときだけ成功する
/// （WWDC21「Bring Recurring Leaderboards to your game」、ドキュメント「Creating recurring leaderboards」）
final class GameKitLeaderboardOccurrence: LeaderboardOccurrence {
    private let leaderboard: GKLeaderboard

    init(leaderboard: GKLeaderboard) {
        self.leaderboard = leaderboard
    }

    var endDate: Date? {
        leaderboard.startDate?.addingTimeInterval(leaderboard.duration)
    }

    func submit(_ score: LeaderboardScore) async throws {
        try await leaderboard.submitScore(score.value, context: score.context, player: GKLocalPlayer.local)
    }
}

/// Game Center のサインインを始める入口。
///
/// 最初のラウンドが終わってから `start()` を呼ぶ（docs/SPEC.md「初回起動と設定」）。いつ呼ぶかのつなぎ込みと、
/// サインインの画面（`signInViewController`）を出すのは、ランキングの画面の PR で行う。
@Observable
final class GameCenterSignIn {
    enum State: Equatable {
        /// まだ始めていない
        case notStarted
        /// GameKit の返事を待っている
        case waiting
        /// サインインの画面を出す必要がある
        case needsSignInScreen
        case signedIn
        /// サインインしていない・できない（断った、スクリーンタイムで制限されている、権限が無いなど）。遊ぶことはできる
        case signedOut
    }

    private(set) var state = State.notStarted
    /// GameKit が渡したサインインの画面
    private(set) var signInViewController: GameCenterViewController?
    /// サインインできたときに呼ぶ（送り直しを始める）
    @ObservationIgnored var onSignedIn: (() -> Void)?
    @ObservationIgnored private let logger = Logger(subsystem: "jp.shilokuma.UncleRAM", category: "Leaderboards")

    /// サインインを始める。2 回目からは何もしない（GameKit は、設定でサインインしたときなどに、同じ handler を何度でも呼ぶ）
    func start() {
        guard state == .notStarted else {
            return
        }
        state = .waiting
        // GameKit は handler をメインスレッドで呼ぶ
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            self?.handleAuthentication(viewController: viewController, error: error)
        }
    }

    private func handleAuthentication(viewController: GameCenterViewController?, error: (any Error)?) {
        if let viewController {
            signInViewController = viewController
            state = .needsSignInScreen
            return
        }
        signInViewController = nil
        if GKLocalPlayer.local.isAuthenticated {
            state = .signedIn
            onSignedIn?()
        } else {
            state = .signedOut
            if let error {
                logger.notice("Game Center sign-in did not complete: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

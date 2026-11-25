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
    /// 1 本のランキングに送る
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

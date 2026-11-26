import GameKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// GameKit が渡す画面（サインイン）と、Game Center の標準の画面を出す
enum GameCenterPresenter {
    /// サインインの画面を、いちばん上の画面に重ねて出す
    static func present(_ viewController: GameCenterViewController) {
        #if os(iOS)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else {
            return
        }
        while let presented = top.presentedViewController {
            top = presented
        }
        top.present(viewController, animated: true)
        #else
        NSApplication.shared.keyWindow?.contentViewController?.presentAsSheet(viewController)
        #endif
    }

    /// Game Center の標準のランキングの画面を開く（docs/SPEC.md「Game Center と名前の扱い」の「Game Center の標準画面への入口」）
    static func showLeaderboards() {
        GKAccessPoint.shared.trigger(state: .leaderboards) {}
    }
}

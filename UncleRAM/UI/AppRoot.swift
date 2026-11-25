import SwiftUI

/// 画面の行き来（タイトル → 速達便のラウンド → 結果 → タイトル、タイトル → 設定）と、初回の案内
struct AppRoot: View {
    enum Destination {
        case title
        case express
        case settings
    }

    @State private var store = LocalStore()
    @State private var destination = AppRoot.initialDestination

    /// 撮影モードのラウンドの場面と、起動引数での計測は、タイトルを通さずにラウンドを開く
    static var initialDestination: Destination {
        switch ScreenshotDemo.scene {
        case .title:
            return .title
        case .settings:
            return .settings
        case .some:
            return .express
        case nil:
            break
        }
        return BenchRunner.isRequestedByLaunchArguments ? .express : .title
    }

    /// 初回の案内を出すか。撮影モードと計測では出さない
    private var showsSafetyNotice: Bool {
        !store.hasAcknowledgedSafetyNotice && !ScreenshotDemo.isEnabled && !BenchRunner.isRequestedByLaunchArguments
    }

    var body: some View {
        ZStack {
            Group {
                switch destination {
                case .title:
                    TitleScreen(
                        onStartExpress: { destination = .express },
                        onOpenSettings: { destination = .settings }
                    )
                    .transition(.opacity)
                case .express:
                    RoundScreen(onExit: { destination = .title })
                        .transition(.opacity)
                case .settings:
                    SettingsScreen(
                        onClose: { destination = .title },
                        onReset: {
                            // 初期化すると初回の案内も消えるので、タイトルに戻ってから、もう一度案内を出す
                            store.resetAll()
                            destination = .title
                        }
                    )
                    .transition(.opacity)
                }
            }
            // 案内を閉じるまでは、下の画面のボタン（return キーの「献上をはじめる」を含む）を押せないようにする
            .disabled(showsSafetyNotice)
            .accessibilityHidden(showsSafetyNotice)
            if showsSafetyNotice {
                SafetyNotice { store.hasAcknowledgedSafetyNotice = true }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: destination)
        .animation(.easeInOut(duration: 0.25), value: showsSafetyNotice)
        .environment(store)
    }
}

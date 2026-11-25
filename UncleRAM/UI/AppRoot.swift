import SwiftUI

/// 画面の行き来（タイトル → 速達便のラウンド → 結果 → タイトル）と、初回の案内
struct AppRoot: View {
    enum Destination {
        case title
        case express
    }

    @State private var store = LocalStore()
    @State private var destination = AppRoot.initialDestination

    /// 撮影モードのラウンドの場面と、起動引数での計測は、タイトルを通さずにラウンドを開く
    static var initialDestination: Destination {
        if let scene = ScreenshotDemo.scene {
            return scene == .title ? .title : .express
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
                    TitleScreen { destination = .express }
                        .transition(.opacity)
                case .express:
                    RoundScreen(onExit: { destination = .title })
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

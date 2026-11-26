import SwiftUI

/// 画面の行き来（タイトル → 速達便のラウンド → 結果 → タイトル、タイトル → 設定・ランキング）と、初回の案内
struct AppRoot: View {
    enum Destination: Equatable {
        case title
        case express
        case daily(DailyChallenge)
        case settings
        case ranking
    }

    @State private var store = LocalStore()
    /// ランキングに送る・サインイン・送り直し
    @State private var ranking = RankingCenter()
    @Environment(\.scenePhase) private var scenePhase
    @State private var destination = AppRoot.initialDestination

    /// 撮影モードのラウンドの場面と、起動引数での計測は、タイトルを通さずにラウンドを開く
    static var initialDestination: Destination {
        switch ScreenshotDemo.scene {
        case .title, .howToPlay:
            return .title
        case .settings:
            return .settings
        case .ranking:
            return .ranking
        case .dailyDelivered:
            return .daily(.today())
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
                        onStartDaily: { destination = .daily($0) },
                        onOpenSettings: { destination = .settings },
                        onOpenRanking: { destination = .ranking }
                    )
                    .transition(.opacity)
                case .express:
                    RoundScreen(onExit: { destination = .title })
                        .transition(.opacity)
                case let .daily(challenge):
                    // その日の種から作った乱数で、最初のラウンドがその日の条件になる（全員同じ回収ライン）
                    RoundScreen(
                        engine: RoundEngine(client: DailyChallenge.client, random: challenge.makeRandom()),
                        mode: .daily(challenge),
                        onExit: { destination = .title }
                    )
                    .transition(.opacity)
                case .ranking:
                    RankingScreen { destination = .title }
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
        .environment(ranking)
        .onAppear {
            // Game Center のサインインは、最初のラウンドを終えてから始める（それまでは RoundScreen が結果のときに始める）。
            // 撮影モードと計測では始めない
            if store.hasCompletedFirstRound, !ScreenshotDemo.isEnabled, !BenchRunner.isRequestedByLaunchArguments {
                ranking.startSignIn()
            }
        }
        .onChange(of: ranking.signIn.state) { _, state in
            if state == .needsSignInScreen, let viewController = ranking.signIn.signInViewController {
                GameCenterPresenter.present(viewController)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, ranking.signIn.state == .signedIn {
                ranking.resendPending()
            }
        }
    }
}

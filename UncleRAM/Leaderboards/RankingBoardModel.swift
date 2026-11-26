import Foundation
import Observation

/// ランキングの画面の選択と読み込み（docs/SPEC.md「ランキング」の「画面」）。
/// 最初は腕前スコアを見せ、「献上量」に切り替えると自分のクラスが開く。ほかのクラスも見られる
@Observable
final class RankingBoardModel {
    enum Category: Equatable {
        case skill
        case donated
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded(LeaderboardPage)
        /// サインインしていない・読めなかった
        case unavailable
    }

    /// 1 回に読む上位の人数
    static let topCount = 25

    var mode: RankingMode = .express { didSet { reload() } }
    var category: Category = .skill { didSet { reload() } }
    /// 献上量のクラス。最初は自分のクラス
    var memoryClass: MemoryClass { didSet { reload() } }
    var scope: LeaderboardScope = .global { didSet { reload() } }
    private(set) var state: LoadState = .idle

    /// 自分のクラス
    let ownClass: MemoryClass
    @ObservationIgnored private let reader: any LeaderboardReading
    @ObservationIgnored private let isSignedIn: () -> Bool
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(ownClass: MemoryClass, reader: any LeaderboardReading = GameKitLeaderboardReader(), isSignedIn: @escaping () -> Bool) {
        self.ownClass = ownClass
        memoryClass = ownClass
        self.reader = reader
        self.isSignedIn = isSignedIn
    }

    /// 今の選択のランキング
    var leaderboard: Leaderboard {
        Leaderboard(mode: mode, kind: category == .skill ? .skill : .donated(memoryClass))
    }

    /// 献上量のクラスの並び。自分の端末の種類のクラスを先に並べる
    var classChoices: [MemoryClass] {
        let isMac = ownClass == .macSmall || ownClass == .macMedium || ownClass == .macLarge
        let mac: [MemoryClass] = [.macSmall, .macMedium, .macLarge]
        let ios: [MemoryClass] = [.iosSmall, .iosMedium, .iosLarge]
        return isMac ? mac + ios : ios + mac
    }

    /// 今の選択で読み直す。前の読み込みは止める
    func reload() {
        loadTask?.cancel()
        guard isSignedIn() else {
            state = .unavailable
            return
        }
        state = .loading
        let leaderboard = leaderboard
        let scope = scope
        loadTask = Task { [weak self, reader] in
            let page = try? await reader.load(leaderboard, scope: scope, top: Self.topCount)
            guard !Task.isCancelled, let self else {
                return
            }
            self.state = page.map { .loaded($0) } ?? .unavailable
        }
    }

    /// 読み込みが終わるまで待つ（テスト用）
    func waitForLoad() async {
        await loadTask?.value
    }
}

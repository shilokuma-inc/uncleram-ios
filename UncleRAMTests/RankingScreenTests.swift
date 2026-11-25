import Foundation
import Testing
@testable import UncleRAM

/// ランキングの画面の選択と読み込み、ラウンドの結果を送るかどうか
struct RankingScreenTests {
    private static let firstDay = DailyDay(year: 2026, month: 12, day: 1)

    private func outcome(_ kind: RoundOutcome.Kind, practice: Bool = false) -> RoundOutcome {
        var random = SplitMix64(seed: 3)
        let plan = practice
            ? RoundPlan.practice(safetyLine: SafetyLine.budgetRatio)
            : RoundPlan.make(client: .allocateCorp, safetyLine: SafetyLine.budgetRatio, random: &random)
        let donated = UInt64(Double(1_073_741_824) * plan.collectionLine * 0.9)
        return RoundOutcome(kind: kind, plan: plan, budgetBytes: 1_073_741_824, donatedBytes: donated, stoppedAtSafetyLine: false)
    }

    private func center(now: Date) -> RankingCenter {
        RankingCenter(
            submitter: RankingSubmitter(service: OfflineService(), store: MemoryStore(), now: { now }),
            device: { DeviceMemoryProfile(kind: .iPhone, nominalGigabytes: 8) },
            now: { now }
        )
    }

    /// 速達便は送り、練習ラウンドは送らない
    @Test
    func expressIsSubmittedButPracticeIsNot() {
        let center = center(now: Self.firstDay.start)
        guard case .submit = center.decision(for: outcome(.delivered), mode: .express) else {
            Issue.record("速達便の納品を送らなかった")
            return
        }
        #expect(center.decision(for: outcome(.delivered, practice: true), mode: .express) == .skip(.practice(.firstRound)))
    }

    /// デイリーは今日の分だけ送り、過去の日（練習）は送らない
    @Test
    func onlyTodaysDailyIsSubmitted() {
        let challenge = DailyChallenge(day: Self.firstDay)
        let today = center(now: Self.firstDay.start.addingTimeInterval(3_600))
        guard case let .submit(record) = today.decision(for: outcome(.delivered), mode: .daily(challenge)) else {
            Issue.record("今日のデイリーを送らなかった")
            return
        }
        #expect(record.round == .daily(Self.firstDay))

        let later = center(now: Self.firstDay.start.addingTimeInterval(86_400 * 2))
        #expect(later.decision(for: outcome(.delivered), mode: .daily(challenge)) == .skip(.practice(.pastDaily)))
    }

    /// 最初は腕前スコア。献上量に切り替えると自分のクラスを開き、クラスは自分の端末の種類を先に並べる
    @Test
    func boardStartsWithSkillAndOwnClass() {
        let model = RankingBoardModel(ownClass: .macMedium, reader: FakeReader()) { true }
        #expect(model.leaderboard == Leaderboard(mode: .express, kind: .skill))
        model.category = .donated
        #expect(model.leaderboard == Leaderboard(mode: .express, kind: .donated(.macMedium)))
        #expect(model.classChoices.prefix(3) == [.macSmall, .macMedium, .macLarge])
        model.mode = .daily
        #expect(model.leaderboard.identifier == "jp.shilokuma.UncleRAM.lb.daily.mb_mac_m")
    }

    /// サインインしていないときは読まずに「見られない」にし、しているときは読んだ順位を出す
    @Test
    func boardLoadsOnlyWhenSignedIn() async {
        let reader = FakeReader()
        let signedOut = RankingBoardModel(ownClass: .iosSmall, reader: reader) { false }
        signedOut.reload()
        #expect(signedOut.state == .unavailable)
        #expect(reader.requests.isEmpty)

        let signedIn = RankingBoardModel(ownClass: .iosSmall, reader: reader) { true }
        signedIn.scope = .friends
        await signedIn.waitForLoad()
        #expect(signedIn.state == .loaded(FakeReader.page))
        #expect(reader.requests.last?.scope == .friends)
    }

    /// 行に添える端末の種類とクラスは、context から読み戻す
    @Test
    func rowShowsDeviceFromContext() {
        let context = LeaderboardContext.encode(kind: .iPad, memoryClass: .iosLarge)
        let row = LeaderboardRow(rank: 1, displayName: "A", score: 10, context: context, isLocalPlayer: false)
        #expect(row.deviceLabel == "iPad・16GB 以上")
        #expect(LeaderboardRow(rank: 2, displayName: "B", score: 5, context: 0, isLocalPlayer: false).deviceLabel == nil)
    }
}

private final class FakeReader: LeaderboardReading {
    static let page = LeaderboardPage(
        rows: [LeaderboardRow(rank: 1, displayName: "A", score: 120, context: 0, isLocalPlayer: true)],
        localPlayer: nil,
        totalPlayers: 1
    )
    private(set) var requests: [(leaderboard: Leaderboard, scope: LeaderboardScope)] = []

    func load(_ leaderboard: Leaderboard, scope: LeaderboardScope, top: Int) async throws -> LeaderboardPage {
        requests.append((leaderboard, scope))
        return Self.page
    }
}

private final class OfflineService: LeaderboardService {
    var isAuthenticated: Bool { false }
    func submit(_ score: LeaderboardScore) async throws {}
    func loadCurrentOccurrence(of leaderboardID: String) async throws -> (any LeaderboardOccurrence)? { nil }
}

private final class MemoryStore: RankingStore {
    var pendingScores = PendingScoreQueue()
    var personalBests = PersonalBests()
}

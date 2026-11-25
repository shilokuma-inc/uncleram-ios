import Foundation
import Testing
@testable import UncleRAM

/// ランキングへの送信・送り直しの待ち行列・自分の最高記録を、偽物の Game Center で確かめる（実際の Game Center には触れない）
struct RankingSubmitterTests {
    // MARK: - 送信と送り直し

    /// サインインしていないときは送らず、貯めもしない。サインインした後にも送らない（サインイン前の記録は送らない）
    @Test
    func signedOutRoundIsNeverSubmitted() async throws {
        let service = FakeLeaderboardService(isAuthenticated: false)
        let store = InMemoryRankingStore()
        let submitter = RankingSubmitter(service: service, store: store)

        await submitter.submit(try Self.record(.express))
        #expect(service.submitted.isEmpty)
        #expect(store.pendingScores.isEmpty)
        // 自分の最高記録は残す
        #expect(store.personalBests.express?.skillScore == 291)

        service.isAuthenticated = true
        await submitter.resendPending()
        #expect(service.submitted.isEmpty)
    }

    @Test
    func signedInRoundSubmitsSkillAndDonated() async throws {
        let service = FakeLeaderboardService()
        let store = InMemoryRankingStore()
        let submitter = RankingSubmitter(service: service, store: store)

        let record = try Self.record(.express)
        await submitter.submit(record)
        #expect(service.submitted == record.leaderboardScores)
        #expect(store.pendingScores.isEmpty)
    }

    @Test
    func failedScoresAreQueuedAndResent() async throws {
        let service = FakeLeaderboardService()
        service.failure = FakeError()
        let store = InMemoryRankingStore()
        let submitter = RankingSubmitter(service: service, store: store)

        let record = try Self.record(.express)
        await submitter.submit(record)
        #expect(store.pendingScores.scores == record.leaderboardScores)

        // まだ送れないあいだは貯めたまま
        await submitter.resendPending()
        #expect(store.pendingScores.scores == record.leaderboardScores)

        service.failure = nil
        await submitter.resendPending()
        #expect(service.submitted == record.leaderboardScores)
        #expect(store.pendingScores.isEmpty)
    }

    /// デイリーはその日（世界標準時）のうちだけ送り直す
    @Test
    func dailyIsResentOnlyWithinTheSameUTCDay() async throws {
        let clock = TestClock(now: try Self.date("2026-12-01T10:00:00Z"))
        let service = FakeLeaderboardService()
        service.failure = FakeError()
        let store = InMemoryRankingStore()
        let submitter = RankingSubmitter(service: service, store: store) { clock.now }

        let record = try Self.record(.daily, recordedAt: clock.now)
        await submitter.submit(record)
        #expect(store.pendingScores.scores.count == 2)

        service.failure = nil
        clock.now = try Self.date("2026-12-01T23:59:59Z")
        await submitter.resendPending()
        #expect(service.submitted == record.leaderboardScores)

        service.failure = FakeError()
        await submitter.submit(record)
        #expect(store.pendingScores.scores.count == 2)

        service.failure = nil
        clock.now = try Self.date("2026-12-02T00:00:00Z")
        await submitter.resendPending()
        #expect(service.submitted.count == 2)
        #expect(store.pendingScores.isEmpty)
    }

    /// 速達便には期限が無いので、日が変わっても送り直す
    @Test
    func expressIsResentOnLaterDays() async throws {
        let clock = TestClock(now: try Self.date("2026-12-01T10:00:00Z"))
        let service = FakeLeaderboardService()
        service.failure = FakeError()
        let store = InMemoryRankingStore()
        let submitter = RankingSubmitter(service: service, store: store) { clock.now }

        await submitter.submit(try Self.record(.express, recordedAt: clock.now))
        service.failure = nil
        clock.now = try Self.date("2026-12-09T10:00:00Z")
        await submitter.resendPending()
        #expect(service.submitted.count == 2)
        #expect(store.pendingScores.isEmpty)
    }

    // MARK: - 待ち行列

    /// 同じランキングの同じ回には、いちばん良いスコアだけを残す
    @Test
    func queueKeepsBestScorePerLeaderboardRound() throws {
        let today = try Self.date("2026-12-02T00:00:00Z")
        let tomorrow = try Self.date("2026-12-03T00:00:00Z")
        var queue = PendingScoreQueue()
        queue.enqueue(Self.score("a", 100))
        queue.enqueue(Self.score("a", 50))
        queue.enqueue(Self.score("a", 200))
        queue.enqueue(Self.score("b", 10))
        queue.enqueue(Self.score("d", 30, expiresAt: today))
        queue.enqueue(Self.score("d", 20, expiresAt: tomorrow))
        #expect(
            queue.scores == [
                Self.score("a", 200),
                Self.score("b", 10),
                Self.score("d", 30, expiresAt: today),
                Self.score("d", 20, expiresAt: tomorrow)
            ]
        )

        queue.removeExpired(at: today)
        #expect(queue.scores == [Self.score("a", 200), Self.score("b", 10), Self.score("d", 20, expiresAt: tomorrow)])
    }

    /// 送れたら、同じランキングの同じ回の低いスコアも要らなくなる。高いスコアは残す
    @Test
    func markSentRemovesCoveredScores() {
        var queue = PendingScoreQueue()
        queue.enqueue(Self.score("a", 100))
        queue.enqueue(Self.score("b", 100))
        queue.markSent(Self.score("a", 150))
        queue.markSent(Self.score("b", 50))
        #expect(queue.scores == [Self.score("b", 100)])
    }

    // MARK: - 自分の最高記録

    /// 腕前と献上量は、ランキングと同じく別々に最高を残す
    @Test
    func expressBestKeepsEachMaximum() throws {
        var bests = PersonalBests()
        bests.record(try Self.record(.express, skill: 250, donated: 1_000))
        bests.record(try Self.record(.express, skill: 120, donated: 3_000))
        #expect(bests.express == PersonalBests.Best(skillScore: 250, donatedScore: 3_000, memoryClass: .iosSmall, expiresAt: nil))
    }

    /// デイリーの最高はその日のうちだけ見せ、次の日は比べずに入れ替える
    @Test
    func dailyBestResetsEveryUTCDay() throws {
        let firstDay = try Self.date("2026-12-01T10:00:00Z")
        let secondDay = try Self.date("2026-12-02T10:00:00Z")
        var bests = PersonalBests()
        bests.record(try Self.record(.daily, recordedAt: firstDay, skill: 250, donated: 3_000))
        #expect(bests.daily(at: firstDay)?.skillScore == 250)
        #expect(bests.daily(at: secondDay) == nil)

        bests.record(try Self.record(.daily, recordedAt: secondDay, skill: 90, donated: 500))
        #expect(bests.daily(at: secondDay)?.skillScore == 90)
        #expect(bests.daily(at: secondDay)?.donatedScore == 500)
        #expect(bests.express == nil)
    }

    /// バックアップから別の端末に移ってクラスが変わったら、献上量は新しいクラスで数え直す（腕前は全端末で共通）
    @Test
    func donatedBestRestartsWhenClassChanges() throws {
        var bests = PersonalBests()
        bests.record(try Self.record(.express, skill: 250, donated: 3_000))
        bests.record(try Self.record(.express, device: DeviceMemoryProfile(kind: .mac, nominalGigabytes: 16), skill: 100, donated: 800))
        #expect(bests.express == PersonalBests.Best(skillScore: 250, donatedScore: 800, memoryClass: .macSmall, expiresAt: nil))
    }

    // MARK: - 保存先

    @Test
    func userDefaultsStoreRoundTrips() throws {
        let suiteName = "UncleRAMTests.ranking.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = UserDefaultsRankingStore(defaults: defaults)
        #expect(store.pendingScores.isEmpty)
        #expect(store.personalBests == PersonalBests())

        let record = try Self.record(.daily)
        store.pendingScores.enqueue(record.leaderboardScores[0])
        store.personalBests.record(record)

        let reopened = UserDefaultsRankingStore(defaults: defaults)
        #expect(reopened.pendingScores.scores == [record.leaderboardScores[0]])
        #expect(reopened.personalBests == store.personalBests)
    }

    /// 読めない値（壊れた値や、形の違う古い値）は空として扱う
    @Test
    func unreadableStoredValuesAreEmpty() throws {
        let suiteName = "UncleRAMTests.ranking.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.set(Data("broken".utf8), forKey: UserDefaultsRankingStore.pendingScoresKey)
        defaults.set(Data("{}".utf8), forKey: UserDefaultsRankingStore.personalBestsKey)

        let store = UserDefaultsRankingStore(defaults: defaults)
        #expect(store.pendingScores.isEmpty)
        #expect(store.personalBests == PersonalBests())
    }

    // MARK: - 補助

    static func record(
        _ mode: RankingMode,
        recordedAt: Date? = nil,
        device: DeviceMemoryProfile = LeaderboardRulesTests.iPhone8GB,
        skill: Int = 291,
        donated: Int = 5_712
    ) throws -> RankingRecord {
        RankingRecord(
            mode: mode,
            skillScore: skill,
            donatedScore: donated,
            device: device,
            recordedAt: try recordedAt ?? date("2026-12-01T10:00:00Z")
        )
    }

    static func score(_ name: String, _ value: Int, expiresAt: Date? = nil) -> LeaderboardScore {
        LeaderboardScore(leaderboardID: name, value: value, context: 111, expiresAt: expiresAt)
    }

    static func date(_ iso8601: String) throws -> Date {
        try LeaderboardRulesTests.date(iso8601)
    }
}

private struct FakeError: Error {}

private final class FakeLeaderboardService: LeaderboardService {
    var isAuthenticated: Bool
    var failure: (any Error)?
    private(set) var submitted: [LeaderboardScore] = []

    init(isAuthenticated: Bool = true) {
        self.isAuthenticated = isAuthenticated
    }

    func submit(_ score: LeaderboardScore) async throws {
        if let failure {
            throw failure
        }
        submitted.append(score)
    }
}

private final class InMemoryRankingStore: RankingStore {
    var pendingScores = PendingScoreQueue()
    var personalBests = PersonalBests()
}

private final class TestClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

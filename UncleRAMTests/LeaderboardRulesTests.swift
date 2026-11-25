import Foundation
import Testing
@testable import UncleRAM

/// ランキングのクラス・ID・context・送らない判定が、docs/SPEC.md「ランキング」のとおりかを確かめる
struct LeaderboardRulesTests {
    // MARK: - 搭載メモリのクラス

    /// physicalMemory は公称より少し少ないので、それ以上でいちばん小さい正式な容量に切り上げる
    @Test(arguments: [
        (3.7, 4),
        (5.6, 6),
        (7.5, 8),
        (11.4, 12),
        (15.5, 16),
        (16.0, 16),
        (17.8, 18),
        (35.6, 36),
        (640.0, 640)
    ])
    func physicalMemoryRoundsUpToNominalCapacity(gigabytes: Double, nominal: Int) {
        let profile = DeviceMemoryProfile(kind: .mac, physicalMemory: Self.bytes(gigabytes: gigabytes))
        #expect(profile.nominalGigabytes == nominal)
    }

    /// iPhone・iPad は 8GB 以下 / 12GB / 16GB 以上、Mac は 16GB 以下 / 24–32GB / 48GB 以上。Mac の 18GB と 36GB は下のクラス
    @Test(arguments: [
        (DeviceKind.iPhone, 4, MemoryClass.iosSmall),
        (.iPhone, 8, .iosSmall),
        (.iPhone, 12, .iosMedium),
        (.iPad, 8, .iosSmall),
        (.iPad, 16, .iosLarge),
        (.iPad, 24, .iosLarge),
        (.mac, 8, .macSmall),
        (.mac, 16, .macSmall),
        (.mac, 18, .macSmall),
        (.mac, 24, .macMedium),
        (.mac, 32, .macMedium),
        (.mac, 36, .macMedium),
        (.mac, 48, .macLarge),
        (.mac, 128, .macLarge)
    ])
    func memoryClassFollowsSpec(kind: DeviceKind, nominalGigabytes: Int, expected: MemoryClass) {
        #expect(DeviceMemoryProfile(kind: kind, nominalGigabytes: nominalGigabytes).memoryClass == expected)
    }

    /// 同じ端末（同じ physicalMemory）なら、毎回同じクラスになる
    @Test
    func sameDeviceAlwaysGetsSameClass() {
        let physicalMemory: UInt64 = 7_981_694_976
        let first = DeviceMemoryProfile(kind: .iPhone, physicalMemory: physicalMemory)
        let second = DeviceMemoryProfile(kind: .iPhone, physicalMemory: physicalMemory)
        #expect(first == second)
        #expect(first.memoryClass == .iosSmall)
    }

    // MARK: - ランキングの ID

    @Test
    func leaderboardIdentifiersFollowNamingRule() {
        #expect(Leaderboard(mode: .express, kind: .skill).identifier == "jp.shilokuma.UncleRAM.lb.express.skill")
        #expect(Leaderboard(mode: .daily, kind: .donated(.macMedium)).identifier == "jp.shilokuma.UncleRAM.lb.daily.mb_mac_m")
        #expect(Leaderboard.all.count == 14)
        #expect(Set(Leaderboard.all.map(\.identifier)).count == 14)
    }

    /// 作った ID が、App Store Connect に送った gamekit の JSON（アプリの直下にコピーされる）の ID と 1 本ずつ一致する
    @Test
    func leaderboardIdentifiersMatchGameKitBundle() throws {
        let url = try #require(
            Bundle.main.url(forResource: "gameCenterResources", withExtension: "json"),
            "gameCenterResources.json がアプリに入っていない"
        )
        let resources = try JSONDecoder().decode(GameCenterResources.self, from: Data(contentsOf: url))
        let bundled = Dictionary(uniqueKeysWithValues: resources.resources.leaderboards.map { ($0.vendorIdentifier, $0) })
        #expect(Set(bundled.keys) == Set(Leaderboard.all.map(\.identifier)))

        for leaderboard in Leaderboard.all {
            let resource = try #require(bundled[leaderboard.identifier])
            // デイリーだけが繰り返し型
            #expect((resource.recurrenceRule != nil) == (leaderboard.mode == .daily), "\(leaderboard.identifier)")
            if leaderboard.kind == .skill {
                #expect(resource.scoreRangeEnd == String(RankingRecord.maximumSkillScore), "\(leaderboard.identifier)")
            }
        }
    }

    // MARK: - context

    @Test
    func contextIsReadableDecimalDigits() {
        #expect(LeaderboardContext.encode(kind: .iPhone, memoryClass: .iosSmall) == 111)
        #expect(LeaderboardContext.encode(kind: .iPad, memoryClass: .iosLarge) == 123)
        #expect(LeaderboardContext.encode(kind: .mac, memoryClass: .macMedium) == 132)
        #expect(LeaderboardContext.encode(DeviceMemoryProfile(kind: .iPad, nominalGigabytes: 12)) == 122)
    }

    @Test
    func contextDecodesBackToKindAndClass() throws {
        for kind in DeviceKind.allCases {
            let classes: [MemoryClass] = kind == .mac ? [.macSmall, .macMedium, .macLarge] : [.iosSmall, .iosMedium, .iosLarge]
            for memoryClass in classes {
                let decoded = try #require(LeaderboardContext.decode(LeaderboardContext.encode(kind: kind, memoryClass: memoryClass)))
                #expect(decoded.kind == kind)
                #expect(decoded.memoryClass == memoryClass)
            }
        }
    }

    /// 0（context を付けていない）、知らない版、知らない種類・大きさは読まない
    @Test(arguments: [0, 13, 213, 103, 143, 110, 114, -113])
    func unknownContextIsNotDecoded(context: Int) {
        #expect(LeaderboardContext.decode(context) == nil)
    }

    // MARK: - 送るかどうか

    @Test
    func deliveredExpressRoundIsSubmitted() throws {
        let recordedAt = try Self.date("2026-12-01T10:00:00Z")
        let decision = RankingRecord.decide(
            outcome: Self.outcome(.delivered),
            mode: .express,
            practice: nil,
            device: Self.iPhone8GB,
            recordedAt: recordedAt
        )
        let record = try #require(Self.record(of: decision))
        #expect(record.skillScore == 291)
        #expect(record.donatedScore == 5_712)
        #expect(record.expiresAt == nil)
        #expect(
            record.leaderboardScores == [
                LeaderboardScore(leaderboardID: "jp.shilokuma.UncleRAM.lb.express.skill", value: 291, context: 111, expiresAt: nil),
                LeaderboardScore(leaderboardID: "jp.shilokuma.UncleRAM.lb.express.mb_ios_s", value: 5_712, context: 111, expiresAt: nil)
            ]
        )
    }

    /// デイリーは遊んだ日の世界標準時 24 時までに送る
    @Test
    func dailyRoundExpiresAtUTCMidnight() throws {
        let decision = RankingRecord.decide(
            outcome: Self.outcome(.audited),
            mode: .daily,
            practice: nil,
            device: DeviceMemoryProfile(kind: .mac, nominalGigabytes: 24),
            recordedAt: try Self.date("2026-12-01T23:59:59Z")
        )
        let record = try #require(Self.record(of: decision))
        let midnight = try Self.date("2026-12-02T00:00:00Z")
        #expect(record.expiresAt == midnight)
        #expect(
            record.leaderboardScores.map(\.leaderboardID) == [
                "jp.shilokuma.UncleRAM.lb.daily.skill",
                "jp.shilokuma.UncleRAM.lb.daily.mb_mac_m"
            ]
        )
        #expect(record.leaderboardScores.allSatisfy { $0.expiresAt == midnight && $0.context == 132 })
        #expect(RankingRecord.endOfUTCDay(containing: midnight) == (try Self.date("2026-12-03T00:00:00Z")))
    }

    /// 回収されたラウンドは 0 を送る
    @Test
    func collectedRoundSubmitsZero() throws {
        let decision = RankingRecord.decide(
            outcome: Self.outcome(.collected, donatedMegabytes: 2_000),
            mode: .express,
            practice: nil,
            device: Self.iPhone8GB,
            recordedAt: try Self.date("2026-12-01T10:00:00Z")
        )
        let record = try #require(Self.record(of: decision))
        #expect(record.skillScore == 0)
        #expect(record.donatedScore == 0)
    }

    @Test(arguments: [
        (RankingPractice?.some(.firstRound), RoundOutcome.Kind.delivered, RankingSkipReason.practice(.firstRound)),
        (.some(.pastDaily), .delivered, .practice(.pastDaily)),
        (nil, .voided(.background), .voided),
        (nil, .voided(.thermal), .voided)
    ])
    func practiceAndVoidedRoundsAreSkipped(practice: RankingPractice?, kind: RoundOutcome.Kind, reason: RankingSkipReason) throws {
        let decision = RankingRecord.decide(
            outcome: Self.outcome(kind),
            mode: .daily,
            practice: practice,
            device: Self.iPhone8GB,
            recordedAt: try Self.date("2026-12-01T10:00:00Z")
        )
        #expect(decision == .skip(reason))
    }

    /// 献上量（倍率をかける前）が端末の搭載メモリを超えるものは送らない
    @Test
    func donationOverDeviceMemoryIsSkipped() throws {
        let decision = RankingRecord.decide(
            outcome: Self.outcome(.delivered),
            mode: .express,
            practice: nil,
            device: DeviceMemoryProfile(kind: .iPhone, nominalGigabytes: 1),
            recordedAt: try Self.date("2026-12-01T10:00:00Z")
        )
        #expect(decision == .skip(.donatedOverMemory))
    }

    /// 腕前は 0〜300 pt、献上量は搭載メモリまで。境目の値は送る
    @Test
    func implausibleValuesAreDetected() {
        let device = Self.iPhone8GB
        #expect(RankingRecord.implausibility(skillScore: 300, donatedBytes: device.memoryBytes, device: device) == nil)
        #expect(RankingRecord.implausibility(skillScore: 0, donatedBytes: 0, device: device) == nil)
        #expect(RankingRecord.implausibility(skillScore: 301, donatedBytes: 0, device: device) == .skillScoreOutOfRange)
        #expect(RankingRecord.implausibility(skillScore: -1, donatedBytes: 0, device: device) == .skillScoreOutOfRange)
        #expect(RankingRecord.implausibility(skillScore: 100, donatedBytes: device.memoryBytes + 1, device: device) == .donatedOverMemory)
    }

    // MARK: - 補助

    static let iPhone8GB = DeviceMemoryProfile(kind: .iPhone, nominalGigabytes: 8)

    /// 枠 3,072MB・回収ライン 64% で 1,904MB を納品すると、ニアミス ×3 で腕前 291 pt・献上量 5,712（GameRulesTests と同じ）
    static func outcome(_ kind: RoundOutcome.Kind, donatedMegabytes: UInt64 = 1_904) -> RoundOutcome {
        let plan = RoundPlan(isEarlyCollection: false, collectionLine: 0.64, hintThresholds: [0.49, 0.56, 0.62], bluffAt: nil)
        return RoundOutcome(
            kind: kind,
            plan: plan,
            budgetBytes: 3_072 * 1_048_576,
            donatedBytes: donatedMegabytes * 1_048_576,
            stoppedAtSafetyLine: false
        )
    }

    static func record(of decision: RankingDecision) -> RankingRecord? {
        guard case .submit(let record) = decision else {
            return nil
        }
        return record
    }

    static func date(_ iso8601: String) throws -> Date {
        try Date.ISO8601FormatStyle().parse(iso8601)
    }

    static func bytes(gigabytes: Double) -> UInt64 {
        UInt64(gigabytes * Double(DeviceMemoryProfile.bytesPerGigabyte))
    }
}

/// gamekit の JSON のうち、確かめるところだけ
nonisolated private struct GameCenterResources: Decodable {
    struct Resources: Decodable {
        let leaderboards: [LeaderboardResource]
    }

    struct LeaderboardResource: Decodable {
        let vendorIdentifier: String
        let scoreRangeEnd: String?
        let recurrenceRule: String?
    }

    let resources: Resources
}

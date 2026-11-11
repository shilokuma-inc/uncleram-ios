import Foundation
import Testing
@testable import UncleRAM

/// 乱数・献上の速さ・回収ラインとヒント・判定の数値が、docs/SPEC.md のとおりかを確かめる
struct GameRulesTests {
    /// SplitMix64 は、どの端末でも同じ種から同じ並びを返す（デイリーの前提）。値は SplitMix64 の参照実装のもの
    @Test
    func splitMix64MatchesReferenceSequence() {
        var random = SplitMix64(seed: 0)
        #expect(random.next() == 0xE220_A839_7B1D_CDAF)
        #expect(random.next() == 0x6E78_9E6A_A1B9_65F4)
        #expect(random.next() == 0x06C4_5D18_8009_454F)
    }

    /// 目安: 30% まで 3.0 秒、55% まで 7.1 秒、80% まで 10.1 秒（docs/SPEC.md「献上の速さ」）
    @Test(arguments: [(0.30, 3.0), (0.55, 7.1), (0.80, 10.1)])
    func donationSpeedMatchesSpecTimeline(target: Double, seconds: Double) {
        #expect(abs(DonationSpeed.secondsToReach(target) - seconds) < 0.15)
    }

    @Test
    func donationSpeedIsCappedAtNinePercent() {
        #expect(DonationSpeed.rate(fill: 0.1, secondsInSlowZone: nil) == 0.10)
        #expect(DonationSpeed.rate(fill: 0.31, secondsInSlowZone: 0) == 0.05)
        #expect(DonationSpeed.rate(fill: 0.7, secondsInSlowZone: 60) == 0.09)
    }

    /// 回収ラインはアロケート社の範囲に収まり、1 割ほどが早期回収、15% ほどにはったりが出る
    @Test
    func roundPlansFollowAllocateCorpDistribution() {
        var random = SplitMix64(seed: 42)
        let count = 20_000
        var early = 0
        var bluffs = 0
        for _ in 0..<count {
            let plan = RoundPlan.make(client: .allocateCorp, safetyLine: 0.85, random: &random)
            let range = plan.isEarlyCollection ? Client.allocateCorp.earlyLineRange : Client.allocateCorp.lineRange
            #expect(range.contains(plan.collectionLine))
            #expect(plan.collectionLine <= 0.80)
            early += plan.isEarlyCollection ? 1 : 0
            if let bluffAt = plan.bluffAt {
                bluffs += 1
                #expect(RoundPlan.bluffRange.contains(bluffAt))
            }
        }
        #expect(abs(Double(early) / Double(count) - 0.10) < 0.01)
        #expect(abs(Double(bluffs) / Double(count) - 0.15) < 0.01)
    }

    /// ヒントは必ず 1 → 2 → 3 の順に、回収ラインより手前に出る
    @Test
    func hintThresholdsAreOrderedAndBeforeLine() {
        var random = SplitMix64(seed: 7)
        for _ in 0..<5_000 {
            let plan = RoundPlan.make(client: .allocateCorp, safetyLine: 0.85, random: &random)
            #expect(plan.hintThresholds.count == 3)
            #expect(plan.hintThresholds[0] < plan.hintThresholds[1])
            #expect(plan.hintThresholds[1] < plan.hintThresholds[2])
            #expect(plan.hintThresholds[2] < plan.collectionLine)
            #expect(plan.hintStage(at: plan.hintThresholds[1]) == .approach)
            #expect(plan.hintStage(at: 0) == .none)
        }
    }

    /// 回収ラインは「安全ライン − 枠の 5%」を越えない（枠が小さく、安全ラインが手前になる端末でも）
    @Test
    func collectionLineStaysBelowSafetyLine() {
        var random = SplitMix64(seed: 3)
        for _ in 0..<2_000 {
            let plan = RoundPlan.make(client: .allocateCorp, safetyLine: 0.62, random: &random)
            #expect(plan.collectionLine <= 0.57 + 1e-9)
        }
    }

    /// 同じ種なら、同じ条件のラウンドになる（デイリーで全員が同じになる前提）
    @Test
    func sameSeedMakesSamePlan() {
        var first = SplitMix64(seed: 20_261_112)
        var second = SplitMix64(seed: 20_261_112)
        #expect(
            RoundPlan.make(client: .allocateCorp, safetyLine: 0.85, random: &first)
                == RoundPlan.make(client: .allocateCorp, safetyLine: 0.85, random: &second)
        )
    }

    @Test(arguments: [
        (0.02, true, 3.0),
        (0.03, true, 3.0),
        (0.05, true, 1.5),
        (0.10, true, 1.5),
        (0.11, true, 1.0),
        (0.01, false, 1.0),
        (-0.01, true, 1.0)
    ])
    func nearMissMultiplier(gap: Double, successful: Bool, expected: Double) {
        #expect(RoundOutcome.nearMissMultiplier(gap: gap, successful: successful) == expected)
    }

    /// スコア = 献上量（MB）× ニアミス倍率。腕前スコアは到達率 × 倍率（最大 300）。回収されたら 0
    @Test
    func scoresFollowSpec() {
        let plan = RoundPlan(isEarlyCollection: false, collectionLine: 0.64, hintThresholds: [0.49, 0.56, 0.62], bluffAt: nil)
        let budget: UInt64 = 3_072 * 1_048_576
        let delivered = RoundOutcome(
            kind: .delivered,
            plan: plan,
            budgetBytes: budget,
            donatedBytes: 1_904 * 1_048_576,
            stoppedAtSafetyLine: false
        )
        #expect(delivered.nearMissMultiplier == 3)
        #expect(delivered.score == 5_712)
        #expect(delivered.skillScore == 291)

        let collected = RoundOutcome(
            kind: .collected,
            plan: plan,
            budgetBytes: budget,
            donatedBytes: 2_000 * 1_048_576,
            stoppedAtSafetyLine: false
        )
        #expect(collected.score == 0)
        #expect(collected.skillScore == 0)
    }

    /// 「Mac で増設すると」の換算はデザインの値になる（円は 10 円、ドルは 1 ドル単位で切り捨て）
    @Test
    func macUpgradePriceMatchesDesign() {
        let japan = MacUpgradePrice.japan
        #expect(japan.amount(for: 1_248 * 1_048_576) == 5_480)
        #expect(japan.amount(for: 3_412 * 1_048_576) == 14_990)
        #expect(MacUpgradePrice.unitedStates.amount(for: 1_248 * 1_048_576) == 30)
    }
}

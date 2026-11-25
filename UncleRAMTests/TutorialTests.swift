import Foundation
import Testing
@testable import UncleRAM

/// 練習ラウンドと、最初の 1 回で覚えることの吹き出し（docs/SPEC.md「説明なしで分かる UI」）
struct TutorialTests {
    /// テストごとの UserDefaults（終わったら消す）
    private struct Suite {
        let name = "UncleRAMTests.\(UUID().uuidString)"
        let defaults: UserDefaults

        init() throws {
            defaults = try #require(UserDefaults(suiteName: name))
        }

        func remove() {
            defaults.removePersistentDomain(forName: name)
        }
    }

    /// 練習ラウンドは、回収ラインを枠の 50% に固定し、ヒントを揺らがせずに 15%・8%・2% 手前に出す。早期回収とはったりは出さない
    @Test
    func practicePlanFixesLineAtHalf() {
        let plan = RoundPlan.practice(safetyLine: SafetyLine.budgetRatio)
        #expect(plan.isPractice)
        #expect(plan.collectionLine == 0.5)
        #expect(plan.hintThresholds.map { ($0 * 1_000).rounded() / 1_000 } == [0.35, 0.42, 0.48])
        #expect(!plan.isEarlyCollection)
        #expect(plan.bluffAt == nil)
    }

    /// 枠が小さく安全ラインが手前の端末では、練習ラウンドのラインも「安全ライン − 枠の 5%」で頭打ちになる
    @Test
    func practicePlanStaysBelowSafetyLine() {
        let plan = RoundPlan.practice(safetyLine: 0.5)
        #expect(plan.collectionLine == 0.45)
        #expect(plan.hintThresholds[2] < plan.collectionLine)
    }

    /// 練習ラウンドの条件は乱数を使わないので、普段のラウンドは練習のあとも同じ並びになる
    @Test
    func normalPlansAreNotPractice() {
        var random = SplitMix64(seed: 1)
        #expect(!RoundPlan.make(client: .allocateCorp, safetyLine: SafetyLine.budgetRatio, random: &random).isPractice)
    }

    /// 吹き出しは一度だけ出し、見たことを端末に覚えておく
    @Test
    func coachRevealsEachBubbleOnce() throws {
        let suite = try Suite()
        defer { suite.remove() }
        let store = LocalStore(defaults: suite.defaults)
        let coach = TutorialCoach(store: store)

        coach.reveal(.releaseToDeliver)
        #expect(coach.current == .releaseToDeliver)
        coach.dismiss()
        coach.reveal(.releaseToDeliver)
        #expect(coach.current == nil)
        #expect(LocalStore(defaults: suite.defaults).seenTutorialBubbles == [TutorialBubble.releaseToDeliver.rawValue])
    }

    /// 端末の記録を渡さないとき（撮影モード・計測）は、吹き出しを出さない
    @Test
    func coachWithoutStoreShowsNothing() {
        let coach = TutorialCoach()
        coach.reveal(.sign)
        #expect(coach.current == nil)
    }

    /// 新しい吹き出しを出すと、前の吹き出しは消える（一度に 1 つ）
    @Test
    func coachShowsOneBubbleAtATime() throws {
        let suite = try Suite()
        defer { suite.remove() }
        let store = LocalStore(defaults: suite.defaults)
        let coach = TutorialCoach(store: store)

        coach.reveal(.sign)
        coach.reveal(.approach)
        #expect(coach.current == .approach)
    }

    /// ヒントの段階ごとの吹き出し
    @Test
    func hintStagesHaveBubbles() {
        #expect(TutorialBubble.forHintStage(.none) == nil)
        #expect(TutorialBubble.forHintStage(.sign) == .sign)
        #expect(TutorialBubble.forHintStage(.approach) == .approach)
        #expect(TutorialBubble.forHintStage(.warning) == .warning)
    }

    /// 練習ラウンドを納品か回収で終えたら「練習を終えた」にし、無効になったら（納品のあとで無効に変わったときも）取り消す
    @Test
    func practiceCompletionFollowsOutcome() {
        let practice = RoundPlan.practice(safetyLine: SafetyLine.budgetRatio)
        func outcome(_ kind: RoundOutcome.Kind, plan: RoundPlan = practice) -> RoundOutcome {
            RoundOutcome(kind: kind, plan: plan, budgetBytes: 1_000, donatedBytes: 300, stoppedAtSafetyLine: false)
        }
        #expect(RoundScreen.practiceCompletion(after: outcome(.delivered)) == true)
        #expect(RoundScreen.practiceCompletion(after: outcome(.collected)) == true)
        #expect(RoundScreen.practiceCompletion(after: outcome(.voided(.background))) == false)
        var random = SplitMix64(seed: 1)
        let normal = RoundPlan.make(client: .allocateCorp, safetyLine: SafetyLine.budgetRatio, random: &random)
        #expect(RoundScreen.practiceCompletion(after: outcome(.voided(.background), plan: normal)) == nil)
    }

    /// タップで献上のときは、離しても納品しないので「もう一度押せば納品だ」と伝える
    @Test
    func releaseBubbleFollowsTapSetting() {
        #expect(TutorialBubble.releaseToDeliver.announcement(tapToDonate: false) == String(localized: "離せば納品だ"))
        #expect(TutorialBubble.releaseToDeliver.announcement(tapToDonate: true) == String(localized: "もう一度押せば納品だ"))
        #expect(TutorialBubble.sign.announcement(tapToDonate: true) == TutorialBubble.sign.announcement(tapToDonate: false))
    }

    /// データの初期化は、練習ラウンドを終えたことと、見た吹き出しも消す
    @Test
    func resetAllRestoresTutorial() throws {
        let suite = try Suite()
        defer { suite.remove() }
        let store = LocalStore(defaults: suite.defaults)
        store.hasCompletedFirstRound = true
        store.seenTutorialBubbles = [TutorialBubble.sign.rawValue]

        store.resetAll()
        let reloaded = LocalStore(defaults: suite.defaults)
        #expect(!reloaded.hasCompletedFirstRound)
        #expect(reloaded.seenTutorialBubbles.isEmpty)
    }
}

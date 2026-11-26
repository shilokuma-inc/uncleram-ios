import Foundation
import Testing
@testable import UncleRAM

/// デイリーを画面につなぐ部分（1 日 1 回の記録・タイトルの欄・ラインを明かすか）
struct DailyUITests {
    private static let firstDay = DailyDay(year: 2026, month: 12, day: 1)

    private func outcome(_ kind: RoundOutcome.Kind) -> RoundOutcome {
        var random = SplitMix64(seed: 1)
        let plan = RoundPlan.make(client: .allocateCorp, safetyLine: SafetyLine.budgetRatio, random: &random)
        return RoundOutcome(kind: kind, plan: plan, budgetBytes: 1_073_741_824, donatedBytes: 300 * 1_048_576, stoppedAtSafetyLine: false)
    }

    /// 押し始めた時点でその日の 1 回を使い、無効になっても、その日は挑戦済みのまま
    @Test
    func dailyRecordCountsOnceStarted() {
        let started = DailyRecord.started(on: Self.firstDay)
        #expect(started.isPlayed(on: Self.firstDay))
        #expect(!started.isPlayed(on: DailyDay(year: 2026, month: 12, day: 2)))

        let voided = started.finished(with: outcome(.voided(.background)))
        #expect(voided.result == .voided)
        #expect(voided.isPlayed(on: Self.firstDay))

        let delivered = started.finished(with: outcome(.delivered))
        #expect(delivered.result == .delivered)
        #expect(delivered.score == outcome(.delivered).score)
        #expect(started.finished(with: outcome(.collected)).score == 0)
    }

    /// 記録は次に起動したときも残り、データの初期化で消える
    @Test
    func dailyRecordPersistsAndResets() throws {
        let name = "UncleRAMTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let store = LocalStore(defaults: defaults)
        store.dailyRecord = DailyRecord.started(on: Self.firstDay).finished(with: outcome(.delivered))
        #expect(LocalStore(defaults: defaults).dailyRecord == store.dailyRecord)

        store.resetAll()
        #expect(LocalStore(defaults: defaults).dailyRecord == nil)
    }

    /// 月末（その月の最後の日、世界標準時）だけ「月末につき、ノルマ厳しめ」
    @Test
    func flavorChangesAtMonthEnd() {
        #expect(DailyPanel.flavor(for: DailyDay(year: 2026, month: 12, day: 31)) == "月末につき、ノルマ厳しめ")
        #expect(DailyPanel.flavor(for: DailyDay(year: 2027, month: 2, day: 28)) == "月末につき、ノルマ厳しめ")
        #expect(DailyPanel.flavor(for: DailyDay(year: 2028, month: 2, day: 28)) == "本日も全員、同じ回収ラインです")
        #expect(DailyPanel.flavor(for: Self.firstDay) == "本日も全員、同じ回収ラインです")
    }

    /// 締め切りまでの時間は「時:分:秒」の 2 桁ずつ。過ぎていたら 0
    @Test
    func countdownFormatsHoursMinutesSeconds() {
        let deadline = Self.firstDay.start.addingTimeInterval(86_400)
        #expect(DailyPanel.countdown(until: deadline, now: deadline.addingTimeInterval(-(6 * 3_600 + 41 * 60 + 12))) == "06:41:12")
        #expect(DailyPanel.countdown(until: deadline, now: deadline.addingTimeInterval(5)) == "00:00:00")
    }

    /// 結果で回収ラインを明かすのは、速達便と過去の日だけ。今日のデイリーは明かさない
    @Test
    func dailyHidesLineOnTheDay() {
        let challenge = DailyChallenge(day: Self.firstDay)
        let sameDay = Self.firstDay.start.addingTimeInterval(3_600)
        let nextDay = Self.firstDay.start.addingTimeInterval(86_400 + 3_600)
        #expect(RoundMode.express.revealsCollectionLine(now: sameDay))
        #expect(!RoundMode.daily(challenge).revealsCollectionLine(now: sameDay))
        #expect(RoundMode.daily(challenge).revealsCollectionLine(now: nextDay))
    }

    /// 昨日の回収ラインは、昨日の種から作った条件と同じ
    @Test
    func yesterdayLineMatchesYesterdaysPlan() {
        let today = DailyDay(year: 2026, month: 12, day: 2)
        #expect(DailyPanel.yesterdayLine(before: today) == DailyChallenge(day: Self.firstDay).makePlan().collectionLine)
    }
}

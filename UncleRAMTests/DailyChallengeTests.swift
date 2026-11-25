import Foundation
import Testing
@testable import UncleRAM

/// デイリーの日付・種・条件・通し番号が、docs/SPEC.md「速達便・デイリーの条件と乱数」のとおりかを確かめる。
///
/// 期待値は、アプリのコードを使わずに Python 3（標準の hashlib と datetime）で別に計算した値。
/// CI は iOS Simulator と macOS の両方でこのテストを流すので、端末が違っても同じ値になることも確かめられる。
@MainActor
struct DailyChallengeTests {
    private static let megabyte: UInt64 = 1_048_576

    /// 1970-01-01 からの日数。Python の `(date(2026, 12, 1) - date(1970, 1, 1)).days` などで計算した
    @Test
    func dailyDayCountsDaysSince1970() {
        #expect(DailyDay(year: 1970, month: 1, day: 1).daysSince1970 == 0)
        #expect(DailyDay(year: 2026, month: 12, day: 1).daysSince1970 == 20_788)
        #expect(DailyDay(year: 2028, month: 2, day: 29).daysSince1970 == 21_243)
        #expect(DailyDay(year: 1969, month: 12, day: 31).daysSince1970 == -1)
        #expect(DailyDay(daysSince1970: 21_244).yyyymmdd == "20280301")
        #expect(DailyDay(year: 2026, month: 12, day: 1).yyyymmdd == "20261201")
    }

    /// 年月日の計算が、世界標準時のグレゴリオ暦（Foundation の Calendar）と、1970〜2100 年のすべての日で一致する
    @Test
    func dailyDayMatchesGregorianCalendarInUTC() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let last = DailyDay(year: 2100, month: 12, day: 31).daysSince1970
        var mismatches: [Int] = []
        for days in 0...last {
            let day = DailyDay(daysSince1970: days)
            let expected = calendar.dateComponents([.year, .month, .day], from: day.start)
            let components = day.components
            let sameAsCalendar = components.year == expected.year && components.month == expected.month && components.day == expected.day
            let roundTrips = DailyDay(year: components.year, month: components.month, day: components.day) == day
                && DailyDay(containing: day.start) == day
            if !sameAsCalendar || !roundTrips {
                mismatches.append(days)
            }
        }
        #expect(mismatches.isEmpty)
    }

    /// 世界標準時の 0 時（日本時間 9 時）で次の日に切り替わる。端末のタイムゾーンには左右されない
    @Test
    func dayChangesAtUTCMidnight() throws {
        let formatter = ISO8601DateFormatter()
        let midnight = try #require(formatter.date(from: "2026-12-02T00:00:00Z"))
        let nineInJapan = try #require(formatter.date(from: "2026-12-02T09:00:00+09:00"))
        #expect(nineInJapan == midnight)
        #expect(DailyDay(year: 2026, month: 12, day: 2).start == midnight)

        let first = DailyDay(year: 2026, month: 12, day: 1)
        let second = DailyDay(year: 2026, month: 12, day: 2)
        #expect(DailyDay(containing: midnight.addingTimeInterval(-0.001)) == first)
        #expect(DailyDay(containing: midnight) == second)
        // 日本時間の 8 時 59 分はまだ前の日、9 時ちょうどから次の日
        let beforeNine = try #require(formatter.date(from: "2026-12-02T08:59:59+09:00"))
        #expect(DailyChallenge.today(now: beforeNine).day == first)
        #expect(DailyChallenge.today(now: midnight).day == second)
        // 日付変更線の向こう（UTC−10）では、まだ 12/1 の昼過ぎでも、デイリーは 12/2 に変わる
        let hawaii = try #require(formatter.date(from: "2026-12-01T14:00:00-10:00"))
        #expect(DailyChallenge.today(now: hawaii).day == second)
    }

    /// 種は SHA-256("UncleRAM-daily-v1-" + YYYYMMDD) の先頭 8 バイトを big endian で読んだ値。
    /// Python で `int.from_bytes(hashlib.sha256(b"UncleRAM-daily-v1-20261201").digest()[:8], "big")` と計算した
    /// （`hexdigest()[:16]` の 16 進と同じ値）
    @Test(arguments: [
        (DailyDay(year: 2026, month: 12, day: 1), UInt64(0x97A4_A543_DEDF_A54A)),
        (DailyDay(year: 2026, month: 12, day: 2), UInt64(0x0545_2CC9_54A7_5637)),
        (DailyDay(year: 2026, month: 11, day: 11), UInt64(0x60EA_3D00_89B5_CF28)),
        (DailyDay(year: 2027, month: 1, day: 1), UInt64(0xE472_3665_DC0A_DCCE))
    ])
    func seedIsLeadingEightBytesOfSHA256(day: DailyDay, seed: UInt64) {
        let daily = DailyChallenge(day: day)
        #expect(daily.formula == .v1)
        #expect(daily.formula.seedPrefix == "UncleRAM-daily-v1-")
        #expect(daily.seed == seed)
        var random = daily.makeRandom()
        var reference = SplitMix64(seed: seed)
        #expect(random.next() == reference.next())
    }

    /// 日付から、決まった条件（回収ライン・ヒントの位置・はったり）になる。安全ラインは 85%。
    /// 期待値は、SplitMix64 と `RoundPlan.make` を Python に書き写して計算した（浮動小数点の計算の順番も同じにしたので、値は完全に一致する）:
    ///
    /// ```python
    /// M = 2**64 - 1
    /// state = seed  # 上の seed(...)
    /// def unit():
    ///     global state
    ///     state = (state + 0x9E3779B97F4A7C15) & M
    ///     v = state
    ///     v = ((v ^ (v >> 30)) * 0xBF58476D1CE4E5B9) & M
    ///     v = ((v ^ (v >> 27)) * 0x94D049BB133111EB) & M
    ///     return ((v ^ (v >> 31)) >> 11) * 2.0**-53
    /// uniform = lambda lo, hi: lo + (hi - lo) * unit()
    /// early = unit() < 0.10
    /// line = min(uniform(0.30, 0.50) if early else uniform(0.55, 0.80), max(0.05, 0.85 - 0.05))
    /// hints = []
    /// for distance, jitter in [(0.15, 0.04), (0.08, 0.025), (0.02, 0.02)]:
    ///     position = line - distance + uniform(-jitter, jitter)
    ///     if hints: position = max(position, hints[-1] + 0.005)
    ///     hints.append(max(0.0, position))
    /// hints[2] = min(hints[2], line - 0.005 / 2)
    /// bluff = uniform(0.15, 0.70) if unit() < 0.15 else None
    /// print(early, repr(line), [repr(h) for h in hints], repr(bluff))
    /// ```
    @Test(arguments: [
        // #1。ふつうのラウンド
        (
            DailyDay(year: 2026, month: 12, day: 1),
            RoundPlan(
                isEarlyCollection: false,
                collectionLine: 0.5959400324186384,
                hintThresholds: [0.4580604324125213, 0.526775349803089, 0.565569542570072],
                bluffAt: nil
            )
        ),
        // #2。はったりが出る
        (
            DailyDay(year: 2026, month: 12, day: 2),
            RoundPlan(
                isEarlyCollection: false,
                collectionLine: 0.6109396064699165,
                hintThresholds: [0.4308604063868402, 0.511522155423729, 0.5840182696346158],
                bluffAt: 0.6474734566188238
            )
        ),
        // #7。早期回収
        (
            DailyDay(year: 2026, month: 12, day: 7),
            RoundPlan(
                isEarlyCollection: true,
                collectionLine: 0.4016947982531971,
                hintThresholds: [0.23146981075084677, 0.3243577383805237, 0.3677805135564418],
                bluffAt: nil
            )
        )
    ])
    func dailyPlanIsFixedByDate(day: DailyDay, expected: RoundPlan) {
        let daily = DailyChallenge(day: day)
        #expect(daily.makePlan() == expected)
        #expect(daily.makePlan(safetyLine: SafetyLine.budgetRatio) == expected)
        // 何度作り直しても同じ（1 日のうちに別の端末で開いても同じ）
        #expect(DailyChallenge(day: day).makePlan() == daily.makePlan())
    }

    /// 枠が小さく安全ラインが手前になる端末だけ、回収ラインが「安全ライン − 枠の 5%」で頭打ちになる
    @Test
    func dailyLineIsCappedBelowSmallSafetyLine() {
        let daily = DailyChallenge(day: DailyDay(year: 2026, month: 12, day: 1))
        #expect(daily.makePlan(safetyLine: 0.80).collectionLine == 0.5959400324186384)
        #expect(abs(daily.makePlan(safetyLine: 0.60).collectionLine - 0.55) < 1e-12)
    }

    /// `RoundEngine` に取引先と乱数を渡すと、最初のラウンドがその日の条件になる（ラウンドの前に乱数を使わない）
    @Test
    func roundEngineStartsWithDailyPlan() async throws {
        let daily = DailyChallenge(day: DailyDay(year: 2026, month: 12, day: 2))
        let engine = RoundEngine(
            client: DailyChallenge.client,
            allocator: Allocator(fillMode: .sparse),
            probe: SimulatedMemoryProbe(totalBytes: 2_048 * Self.megabyte),
            random: daily.makeRandom(),
            thermalState: { .nominal }
        )
        engine.beginHold()
        #expect(engine.plan == daily.makePlan(safetyLine: engine.safetyLineFill))
        #expect(engine.plan?.collectionLine == 0.6109396064699165)
        engine.endHold(.released)
        _ = try #require(await engine.waitForResult())
        #expect(engine.allocator.allocatedBytes == 0)
    }

    /// 通し番号は 2026-12-01（世界標準時、仮の起点）を #1 として数える。起点より前の日は番号を持たない
    @Test(arguments: [
        (DailyDay(year: 2026, month: 12, day: 1), 1),
        (DailyDay(year: 2026, month: 12, day: 12), 12),
        (DailyDay(year: 2027, month: 1, day: 1), 32),
        (DailyDay(year: 2027, month: 12, day: 1), 366),
        (DailyDay(year: 2026, month: 11, day: 30), nil),
        (DailyDay(year: 2026, month: 11, day: 11), nil)
    ] as [(DailyDay, Int?)])
    func serialNumberCountsFromFirstDay(day: DailyDay, number: Int?) {
        #expect(DailyChallenge(day: day).number == number)
    }

    /// 今日はランキングに送り、ラインを明かさない。過去の日は練習（送らない・明かす）。まだ来ていない日は遊ばせない
    @Test
    func pastDaysArePracticeAndNotRanked() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-12-12T15:00:00Z"))
        let today = DailyChallenge(day: DailyDay(year: 2026, month: 12, day: 12))
        let yesterday = DailyChallenge(day: DailyDay(year: 2026, month: 12, day: 11))
        let tomorrow = DailyChallenge(day: DailyDay(year: 2026, month: 12, day: 13))

        #expect(DailyChallenge.today(now: now) == today)
        #expect(today.status(now: now) == .today)
        #expect(yesterday.status(now: now) == .practice)
        #expect(DailyChallenge(day: DailyDay(year: 2026, month: 11, day: 11)).status(now: now) == .practice)
        #expect(tomorrow.status(now: now) == .upcoming)
        // 世界標準時の 0 時を過ぎると、今日のデイリーも練習になる
        #expect(today.status(now: DailyDay(year: 2026, month: 12, day: 13).start) == .practice)

        #expect(DailyChallenge.Status.today.isRanked)
        #expect(!DailyChallenge.Status.today.revealsCollectionLine)
        #expect(!DailyChallenge.Status.practice.isRanked)
        #expect(DailyChallenge.Status.practice.revealsCollectionLine)
        #expect(!DailyChallenge.Status.upcoming.isRanked)
        #expect(!DailyChallenge.Status.upcoming.revealsCollectionLine)
    }
}

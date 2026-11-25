import Foundation

/// デイリーの 1 日。世界標準時の暦の日で、世界標準時の 0 時（日本時間 9 時）に次の日へ切り替わる。
///
/// デイリーの種・通し番号・共有リンク（/d/<日付>）・Game Center の繰り返し型ランキングは、どれも世界標準時で数える
/// （docs/SPEC.md「速達便・デイリーの条件と乱数」「Game Center と名前の扱い」）。端末のタイムゾーンや暦（和暦・仏暦など）の
/// 設定で日付が変わらないよう、`Calendar.current` は使わず、1970-01-01 からの日数とグレゴリオ暦の計算だけで扱う。
nonisolated struct DailyDay: Sendable, Hashable, Comparable {
    /// グレゴリオ暦の年月日
    struct Components: Sendable, Hashable {
        let year: Int
        let month: Int
        let day: Int
    }

    private static let secondsPerDay = 86_400.0

    /// 1970-01-01（世界標準時）からの日数
    let daysSince1970: Int

    init(daysSince1970: Int) {
        self.daysSince1970 = daysSince1970
    }

    /// グレゴリオ暦の年月日（世界標準時）から作る。月は 1〜12、日はその月にある日を渡す
    init(year: Int, month: Int, day: Int) {
        daysSince1970 = Self.daysSince1970(year: year, month: month, day: day)
    }

    /// date を含む日。世界標準時の 0 時ちょうどは、新しい日に入る
    init(containing date: Date) {
        daysSince1970 = Int((date.timeIntervalSince1970 / Self.secondsPerDay).rounded(.down))
    }

    /// この日が始まる時刻（世界標準時の 0 時）
    var start: Date {
        Date(timeIntervalSince1970: Double(daysSince1970) * Self.secondsPerDay)
    }

    /// グレゴリオ暦の年月日（世界標準時）
    var components: Components {
        Self.civil(daysSince1970: daysSince1970)
    }

    /// 8 桁の YYYYMMDD（例: 20261201）。デイリーの種と共有リンクに使う
    var yyyymmdd: String {
        let date = components
        return Self.padded(date.year, width: 4) + Self.padded(date.month, width: 2) + Self.padded(date.day, width: 2)
    }

    static func < (lhs: DailyDay, rhs: DailyDay) -> Bool {
        lhs.daysSince1970 < rhs.daysSince1970
    }

    /// 数字を 0 で埋める。`String(format:)` や `DateFormatter` を使わず、どの言語の設定でも半角の数字にする
    private static func padded(_ value: Int, width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    // 年月日と日数の変換は、H. Hinnant の days_from_civil / civil_from_days（グレゴリオ暦をさかのぼって使う暦）。
    // 3 月を年の始めとみなすと、うるう日が年の最後に来るので、400 年（146,097 日）の周期の中を割り算だけで数えられる。
    // 1970-01-01 は、0000-03-01 から 719,468 日目

    private static func daysSince1970(year: Int, month: Int, day: Int) -> Int {
        let marchYear = month <= 2 ? year - 1 : year
        let era = (marchYear >= 0 ? marchYear : marchYear - 399) / 400
        let yearOfEra = marchYear - era * 400
        let monthFromMarch = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * monthFromMarch + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func civil(daysSince1970: Int) -> Components {
        let days = daysSince1970 + 719_468
        let era = (days >= 0 ? days : days - 146_096) / 146_097
        let dayOfEra = days - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthFromMarch = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthFromMarch + 2) / 5 + 1
        let month = monthFromMarch < 10 ? monthFromMarch + 3 : monthFromMarch - 9
        return Components(year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month: month, day: day)
    }
}

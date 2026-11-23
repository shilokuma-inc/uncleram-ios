import Foundation

/// 「Mac で増設すると ○○ 相当」の換算。docs/SPEC.md「金額の表示（Mac 換算＋買取額 ¥0）」。
///
/// 試作では内蔵の値だけを使う（価格表 prices.json の配信は「全部入りの版」で入れる）。
/// 日本は円（¥4,500/GB、税込）、日本以外はドル（$25/GB、税抜き）。
nonisolated struct MacUpgradePrice: Sendable, Equatable {
    /// 1GB あたりの価格
    let pricePerGigabyte: Decimal
    let currencyCode: String
    /// 価格を確かめた時点と、税込みか
    let note: String
    /// 前の時点からの値上がり（2025 年 3 月比）
    let changeNote: String

    static let japan = MacUpgradePrice(
        pricePerGigabyte: 4500,
        currencyCode: "JPY",
        note: String(localized: "（2026年11月・税込）"),
        changeNote: String(localized: "2025年3月比 ▲20%")
    )

    static let unitedStates = MacUpgradePrice(
        pricePerGigabyte: 25,
        currencyCode: "USD",
        note: String(localized: "(Nov 2026, before tax)"),
        changeNote: String(localized: "Still $25/GB. For now.")
    )

    /// 端末の地域で円かドルかを決める（Storefront を使うのは課金を入れるとき）
    static var current: MacUpgradePrice {
        Locale.current.region == .japan ? .japan : .unitedStates
    }

    /// bytes を増設した場合の金額。円は 10 円単位、ドルは 1 ドル単位で切り捨てる（デザインの「¥5,480」「$30」に合わせる）
    func amount(for bytes: UInt64) -> Decimal {
        let gigabytes = Decimal(bytes) / Decimal(1_073_741_824)
        let unit: Decimal = currencyCode == "JPY" ? 10 : 1
        var value = gigabytes * pricePerGigabyte / unit
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .down)
        return rounded * unit
    }

    func formatted(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))
    }

    /// 1GB あたりの価格の表示
    var formattedPricePerGigabyte: String {
        formatted(pricePerGigabyte)
    }
}

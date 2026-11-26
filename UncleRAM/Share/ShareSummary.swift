import Foundation

/// シェアに載せる結果（docs/SPEC.md「共有機能」）。明細書の画像と文字の共有は、どちらもこれだけから作る。
///
/// 載せるのは、献上量・倍率・スコア・金額の元になる値と、モード（速達便・デイリーの日付と通し番号）だけ。
/// 回収ラインの位置と枠（MB）は持たない。デイリーは全員が同じ回収ラインなので、画像にも文字にも正確な位置を出さない
/// （献上率は 10 マスの数だけにする）。名前・端末の ID・Game Center のニックネームも持たない
nonisolated struct ShareSummary: Sendable, Equatable {
    enum Mode: Sendable, Equatable {
        /// 速達便
        case express
        /// デイリー。通し番号は `DailyChallenge.number`（起点より前の日は nil で、番号を省く）
        case daily(day: DailyDay, number: Int?)

        init(daily: DailyChallenge) {
            self = .daily(day: daily.day, number: daily.number)
        }
    }

    /// 終わり方。無効になったラウンド（店じまい）はシェアしない
    enum Result: Sendable, Equatable {
        case delivered
        case collected
        case audited
    }

    /// 10 マスの絵文字のマスの数
    static let squareCount = 10

    let mode: Mode
    let result: Result
    let donatedBytes: UInt64
    /// 10 マスのうち埋めるマスの数。枠に対する献上率を 10% 刻みで切り捨てる
    let filledSquares: Int
    let nearMissMultiplier: Double
    let score: Int
    /// 明細書の「○年○月分」（グレゴリオ暦）
    let year: Int
    let month: Int

    /// - Parameters:
    ///   - issuedAt: 明細書の日付にする時刻。デイリーは、その日（世界標準時）の年月にする
    ///   - calendar: 速達便の年月を数える暦。端末の暦の設定（和暦など）に左右されないよう、グレゴリオ暦で数える
    /// - Returns: 無効になったラウンドは nil（シェアしない）
    init?(outcome: RoundOutcome, mode: Mode, issuedAt: Date = .now, calendar: Calendar = Calendar(identifier: .gregorian)) {
        switch outcome.kind {
        case .delivered:
            result = .delivered
        case .collected:
            result = .collected
        case .audited:
            result = .audited
        case .voided:
            return nil
        }
        self.mode = mode
        donatedBytes = outcome.donatedBytes
        filledSquares = Self.squares(for: outcome.releasedFill)
        nearMissMultiplier = outcome.nearMissMultiplier
        score = outcome.score
        switch mode {
        case .express:
            let components = calendar.dateComponents([.year, .month], from: issuedAt)
            year = components.year ?? 0
            month = components.month ?? 0
        case let .daily(day, _):
            year = day.components.year
            month = day.components.month
        }
    }

    /// 枠に対する献上率（0〜1）を、10% 刻みで切り捨てたマスの数にする。浮動小数の誤差（0.7 が 0.6999… になる）で 1 マス減らないよう、少しだけ足してから切り捨てる
    static func squares(for fill: Double) -> Int {
        let clamped = min(max(fill, 0), 1)
        return min(squareCount, Int((clamped * Double(squareCount) + 1e-9).rounded(.down)))
    }

    var isCollected: Bool {
        result == .collected
    }

    /// 献上量（MB。切り捨て）
    var donatedMegabytes: UInt64 {
        donatedBytes / 1_048_576
    }
}

/// 紹介ページへのリンク（docs/SPEC.md「共有機能」の「リンク」）
nonisolated enum ShareLinks {
    /// 紹介ページの URL（末尾の / は付けない。例: "https://example.com"）。
    /// 置き場所がまだ決まっていないので空にしている。決まったらここに入れる。空のあいだは、文字の共有にリンクを付けない
    static let introductionPage = ""

    /// モードごとのリンク。デイリーは /d/<世界標準時の YYYYMMDD>（アプリが入っていれば Universal Links でその日のデイリーを開く）。
    /// URL には利用者を特定できる情報を入れない
    static func link(for mode: ShareSummary.Mode, base: String = introductionPage) -> URL? {
        guard !base.isEmpty else {
            return nil
        }
        switch mode {
        case .express:
            return URL(string: base)
        case let .daily(day, _):
            return URL(string: "\(base)/d/\(day.yyyymmdd)")
        }
    }
}

/// 文字の共有の定型文と、画像に添える初期文面（docs/SPEC.md「共有機能」の「文字の共有の例」「初期文面」）
nonisolated enum ShareText {
    /// ハッシュタグ。「#UncleRAM」は全言語で共通、日本語は「#メモリ高騰」も入れる
    static var hashtags: String {
        String(localized: "#UncleRAM #メモリ高騰", comment: "日本語以外の言語は #UncleRAM だけにする")
    }

    /// 10 マスの絵文字。献上率の分だけ赤く塗り、回収されたら最後に塗ったマスを 💥 にする（回収されたときは少なくとも 1 マス）
    static func squares(filled: Int, collected: Bool) -> String {
        let count = min(max(collected ? max(filled, 1) : filled, 0), ShareSummary.squareCount)
        let red = collected ? count - 1 : count
        return String(repeating: "🟥", count: red)
            + (collected ? "💥" : "")
            + String(repeating: "⬜", count: ShareSummary.squareCount - count)
    }

    /// 文字の共有の定型文
    ///
    ///     Uncle RAM デイリー #12（12/12）
    ///     🟥🟥🟥🟥🟥🟥🟥⬜⬜⬜ 納品成功
    ///     献上 2,410MB（ニアミス ×3）→ 買取額 ¥0
    ///     iPhone 17 Pro（12GB）
    ///     #UncleRAM #メモリ高騰 https://（紹介ページ）/d/20261212
    static func post(_ summary: ShareSummary, device: String, price: MacUpgradePrice, link: URL?, locale: Locale = .current) -> String {
        let megabytes = number(summary.donatedMegabytes, locale: locale)
        let zero = price.formatted(0)
        let donation = if summary.nearMissMultiplier > 1 {
            String(localized: "献上 \(megabytes)MB（ニアミス ×\(multiplier(summary.nearMissMultiplier, locale: locale))）→ 買取額 \(zero)")
        } else {
            String(localized: "献上 \(megabytes)MB → 買取額 \(zero)")
        }
        return [
            title(summary.mode),
            "\(squares(filled: summary.filledSquares, collected: summary.isCollected)) \(status(summary.result))",
            donation,
            device,
            footer(link: link)
        ].joined(separator: "\n")
    }

    /// 画像に添える初期文面（共有シートで、画像と一緒に渡す）
    static func caption(
        _ summary: ShareSummary,
        deviceName: String,
        price: MacUpgradePrice,
        link: URL?,
        locale: Locale = .current
    ) -> String {
        let megabytes = number(summary.donatedMegabytes, locale: locale)
        let zero = price.formatted(0)
        let sentence = summary.isCollected
            ? String(localized: "\(deviceName) で \(megabytes) MB を献上し、全額回収されました。買取額は \(zero) でした。")
            : String(localized: "\(deviceName) で \(megabytes) MB を献上しました。買取額は \(zero) でした。")
        return sentence + "\n" + footer(link: link)
    }

    /// 1 行目。速達便は「Uncle RAM 速達便」、デイリーは「Uncle RAM デイリー #12（12/12）」（日付は世界標準時の月/日）
    static func title(_ mode: ShareSummary.Mode) -> String {
        switch mode {
        case .express:
            return String(localized: "Uncle RAM 速達便")
        case let .daily(day, number):
            let date = "\(day.components.month)/\(day.components.day)"
            guard let number else {
                return String(localized: "Uncle RAM デイリー（\(date)）")
            }
            return String(localized: "Uncle RAM デイリー #\(number)（\(date)）")
        }
    }

    static func status(_ result: ShareSummary.Result) -> String {
        switch result {
        case .delivered:
            String(localized: "納品成功")
        case .audited:
            String(localized: "監査で納品")
        case .collected:
            String(localized: "全メモリ回収")
        }
    }

    private static func footer(link: URL?) -> String {
        guard let link else {
            return hashtags
        }
        return "\(hashtags) \(link.absoluteString)"
    }

    private static func number(_ value: UInt64, locale: Locale) -> String {
        Int(value).formatted(.number.locale(locale))
    }

    /// 3 → 「3」、1.5 → 「1.5」
    private static func multiplier(_ value: Double, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }
}

import Foundation
import Testing
@testable import UncleRAM

/// 結果の共有（docs/SPEC.md「共有機能」）。文字の定型文・10 マスの絵文字・機種名の引き当て・端末の表示の切り替え・書き出す画像の大きさを確かめる
@MainActor
struct ShareTests {
    private static let megabyte: UInt64 = 1_048_576
    private static let japanese = Locale(identifier: "ja_JP")
    private static let iPhone17Pro = ShareDeviceLabel(
        kind: .iPhone,
        nominalGigabytes: 12,
        model: DeviceModel(name: "iPhone 17 Pro")
    )

    /// 枠 4,096 MB のラウンドで、donated MB を献上した結果
    private static func outcome(_ kind: RoundOutcome.Kind, donated: UInt64, line: Double = 0.60) -> RoundOutcome {
        RoundOutcome(
            kind: kind,
            plan: RoundPlan(
                isEarlyCollection: false,
                collectionLine: line,
                hintThresholds: [line - 0.15, line - 0.08, line - 0.02],
                bluffAt: nil
            ),
            budgetBytes: 4_096 * megabyte,
            donatedBytes: donated * megabyte,
            stoppedAtSafetyLine: false
        )
    }

    private static func summary(_ outcome: RoundOutcome, mode: ShareSummary.Mode = .express) throws -> ShareSummary {
        try #require(ShareSummary(outcome: outcome, mode: mode))
    }

    // MARK: - 10 マスの絵文字

    /// 枠に対する献上率を 10% 刻みで切り捨てる。ちょうど 70% は（浮動小数の誤差があっても）7 マス
    @Test
    func squaresFloorFillToTenPercentSteps() {
        #expect(ShareSummary.squares(for: 0) == 0)
        #expect(ShareSummary.squares(for: 0.099) == 0)
        #expect(ShareSummary.squares(for: 0.1) == 1)
        #expect(ShareSummary.squares(for: 0.7) == 7)
        #expect(ShareSummary.squares(for: 0.1 * 7) == 7)
        #expect(ShareSummary.squares(for: 0.789) == 7)
        #expect(ShareSummary.squares(for: 0.85) == 8)
        #expect(ShareSummary.squares(for: 1) == 10)
        #expect(ShareSummary.squares(for: 1.2) == 10)
        #expect(ShareSummary.squares(for: -0.1) == 0)
    }

    /// 納品は赤と白の 10 マス。回収されたら、最後に塗ったマスを 💥 にする（少なくとも 1 マス）
    @Test
    func squaresMarkCollectionWithExplosion() {
        #expect(ShareText.squares(filled: 7, collected: false) == "🟥🟥🟥🟥🟥🟥🟥⬜⬜⬜")
        #expect(ShareText.squares(filled: 0, collected: false) == "⬜⬜⬜⬜⬜⬜⬜⬜⬜⬜")
        #expect(ShareText.squares(filled: 7, collected: true) == "🟥🟥🟥🟥🟥🟥💥⬜⬜⬜")
        #expect(ShareText.squares(filled: 0, collected: true) == "💥⬜⬜⬜⬜⬜⬜⬜⬜⬜")
        #expect(ShareText.squares(filled: 10, collected: true) == "🟥🟥🟥🟥🟥🟥🟥🟥🟥💥")
        for filled in 0...10 {
            #expect(ShareText.squares(filled: filled, collected: false).count == 10)
            #expect(ShareText.squares(filled: filled, collected: true).count == 10)
        }
    }

    // MARK: - 文字の共有

    /// 速達便の定型文（docs/SPEC.md の例の 1 行目を速達便にしたもの）。ニアミスの倍率と、買取額 0、端末の表示、ハッシュタグが入る
    @Test
    func expressPostMatchesTemplate() throws {
        // 2,410 / 4,096 = 58.8% → 5 マス。回収ラインまで枠の 1.2% なのでニアミス ×3
        let summary = try Self.summary(Self.outcome(.delivered, donated: 2_410))
        let price = MacUpgradePrice.japan
        let text = ShareText.post(summary, device: Self.iPhone17Pro.text(hidesModel: false), price: price, link: nil, locale: Self.japanese)
        #expect(text == """
        Uncle RAM 速達便
        🟥🟥🟥🟥🟥⬜⬜⬜⬜⬜ 納品成功
        献上 2,410MB（ニアミス ×3）→ 買取額 \(price.formatted(0))
        iPhone 17 Pro（12GB）
        #UncleRAM #メモリ高騰
        """)
    }

    /// デイリーの定型文。通し番号と世界標準時の日付、回収されたときの 💥 と「全メモリ回収」、日付つきのリンクが入る
    @Test
    func dailyPostMatchesTemplate() throws {
        let daily = DailyChallenge(day: DailyDay(year: 2026, month: 12, day: 12))
        #expect(daily.number == 12)
        // 2,498 / 4,096 = 61.0% → 6 マスで、6 マス目が 💥
        let summary = try Self.summary(Self.outcome(.collected, donated: 2_498), mode: ShareSummary.Mode(daily: daily))
        let price = MacUpgradePrice.japan
        let link = ShareLinks.link(for: summary.mode, base: "https://example.com")
        #expect(link?.absoluteString == "https://example.com/d/20261212")
        let text = ShareText.post(summary, device: "iPhone（12GB 級）", price: price, link: link, locale: Self.japanese)
        #expect(text == """
        Uncle RAM デイリー #12（12/12）
        🟥🟥🟥🟥🟥💥⬜⬜⬜⬜ 全メモリ回収
        献上 2,498MB → 買取額 \(price.formatted(0))
        iPhone（12GB 級）
        #UncleRAM #メモリ高騰 https://example.com/d/20261212
        """)
    }

    /// 通し番号の起点より前の日（公開前の TestFlight など）は、番号を省く
    @Test
    func dailyTitleOmitsNumberBeforeFirstDay() {
        let daily = DailyChallenge(day: DailyDay(year: 2026, month: 11, day: 30))
        #expect(daily.number == nil)
        #expect(ShareText.title(ShareSummary.Mode(daily: daily)) == "Uncle RAM デイリー（11/30）")
        #expect(ShareText.title(.express) == "Uncle RAM 速達便")
    }

    /// 監査（メモリ警告）は納品扱いなので「監査で納品」。倍率 ×1.5 は小数 1 桁まで出す
    @Test
    func auditedPostSaysDeliveredByAudit() throws {
        // 2,048 / 4,096 = 50%。回収ラインまで枠の 5% なので ×1.5
        let summary = try Self.summary(Self.outcome(.audited, donated: 2_048, line: 0.55))
        let text = ShareText.post(summary, device: "iPad（16GB 級）", price: .unitedStates, link: nil, locale: Self.japanese)
        let lines = text.components(separatedBy: "\n")
        #expect(lines[1] == "🟥🟥🟥🟥🟥⬜⬜⬜⬜⬜ 監査で納品")
        #expect(lines[2] == "献上 2,048MB（ニアミス ×1.5）→ 買取額 \(MacUpgradePrice.unitedStates.formatted(0))")
    }

    /// 紹介ページの URL が空のあいだは、リンクを付けない（速達便もデイリーも）
    @Test
    func emptyIntroductionPageAddsNoLink() throws {
        let daily = ShareSummary.Mode(daily: DailyChallenge(day: DailyDay(year: 2026, month: 12, day: 12)))
        #expect(ShareLinks.link(for: .express, base: "") == nil)
        #expect(ShareLinks.link(for: daily, base: "") == nil)
        #expect(ShareLinks.link(for: .express, base: "https://example.com")?.absoluteString == "https://example.com")

        let summary = try Self.summary(Self.outcome(.delivered, donated: 1_000))
        let text = ShareText.post(summary, device: "iPhone（12GB 級）", price: .japan, link: nil, locale: Self.japanese)
        #expect(text.hasSuffix("\n#UncleRAM #メモリ高騰"))
    }

    /// 画像に添える初期文面。機種名（隠すときは iPhone・iPad・Mac）と献上量、買取額が入る
    @Test
    func captionMentionsDeviceAndZeroPrice() throws {
        let price = MacUpgradePrice.japan
        let delivered = try Self.summary(Self.outcome(.delivered, donated: 2_410))
        #expect(ShareText.caption(delivered, deviceName: "iPhone 17 Pro", price: price, link: nil, locale: Self.japanese) == """
        iPhone 17 Pro で 2,410 MB を献上しました。買取額は \(price.formatted(0)) でした。
        #UncleRAM #メモリ高騰
        """)
        let collected = try Self.summary(Self.outcome(.collected, donated: 2_498))
        let link = URL(string: "https://example.com")
        #expect(ShareText.caption(collected, deviceName: "iPhone", price: price, link: link, locale: Self.japanese) == """
        iPhone で 2,498 MB を献上し、全額回収されました。買取額は \(price.formatted(0)) でした。
        #UncleRAM #メモリ高騰 https://example.com
        """)
    }

    /// デイリーは回収ラインの位置を出さない。シェアの中身はラインを持たないので、ラインが違っても同じ量で離せば同じ文面と明細書になる
    @Test
    func dailyShareDoesNotDependOnCollectionLine() throws {
        let mode = ShareSummary.Mode(daily: DailyChallenge(day: DailyDay(year: 2026, month: 12, day: 12)))
        // どちらも回収ラインまで枠の 10% より離れているので、倍率は付かない
        let early = try Self.summary(Self.outcome(.delivered, donated: 2_048, line: 0.75), mode: mode)
        let late = try Self.summary(Self.outcome(.delivered, donated: 2_048, line: 0.80), mode: mode)
        #expect(early == late)
        let text = ShareText.post(early, device: "iPhone（12GB 級）", price: .japan, link: nil, locale: Self.japanese)
        #expect(!text.contains("%"))
        #expect(!text.contains("ライン"))
    }

    /// 無効になったラウンド（店じまい）はシェアしない
    @Test
    func voidedRoundIsNotShared() {
        #expect(ShareSummary(outcome: Self.outcome(.voided(.background), donated: 1_000), mode: .express) == nil)
    }

    /// 明細書の「○年○月分」。速達便は端末の時刻のグレゴリオ暦、デイリーはその日（世界標準時）の年月
    @Test
    func statementMonthFollowsModeAndGregorianCalendar() throws {
        // 世界標準時 2026-11-30 20:00 は、日本時間では 12 月 1 日
        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-30T20:00:00Z"))
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let delivered = Self.outcome(.delivered, donated: 1_000)
        let express = try #require(ShareSummary(outcome: delivered, mode: .express, issuedAt: date, calendar: tokyo))
        #expect(express.year == 2026)
        #expect(express.month == 12)

        let daily = DailyChallenge(day: DailyDay(containing: date))
        let summary = try #require(ShareSummary(outcome: delivered, mode: ShareSummary.Mode(daily: daily), issuedAt: date, calendar: tokyo))
        #expect(summary.year == 2026)
        #expect(summary.month == 11)
    }

    // MARK: - 明細書の値

    /// 用途の秒数は献上量から計算する架空の値。デザインの例（4,210 MB で 0.0003 秒、21,480 MB で 0.0015 秒）になる
    @Test
    func usageSecondsMatchDesignExamples() throws {
        func usage(_ megabytes: UInt64) throws -> String {
            let summary = try Self.summary(Self.outcome(.delivered, donated: megabytes, line: 0.99))
            let content = TributeStatementContent(summary: summary, device: "", price: .japan, isMac: false)
            return content.usageSecondsText(locale: Self.japanese)
        }
        #expect(try usage(4_210) == "0.0003")
        #expect(try usage(21_480) == "0.0015")
        // 小数 4 桁で 0 になるほど少ないときは、0 でない桁まで出す
        #expect(try usage(300) == "0.00002")
        #expect(try usage(0) == "0.0000")
    }

    // MARK: - 機種名の対応表と端末の表示

    /// 同梱の対応表を `Bundle.main` から読める。主な機種が入っていて、機種 ID の頭が端末の種類と合っている
    @Test
    func bundledCatalogHasMainModels() {
        let catalog = DeviceModelCatalog.bundled
        #expect(!catalog.checkedOn.isEmpty)
        #expect(catalog.model(for: "iPhone18,1") == DeviceModel(name: "iPhone 17 Pro"))
        #expect(catalog.model(for: "iPhone14,6") == DeviceModel(name: "iPhone SE", generation: 3))
        #expect(catalog.model(for: "iPad16,5") == DeviceModel(name: "iPad Pro", inches: "13", chip: "M4"))
        #expect(catalog.model(for: "Mac17,3") == DeviceModel(name: "MacBook Air", chip: "M5"))
        #expect(catalog.model(for: "Mac16,10") == DeviceModel(name: "Mac mini"))
        #expect(catalog.model(for: "iPhone99,9") == nil)

        let prefixes = ["iPhone", "iPad", "Mac", "MacBookAir", "MacBookPro", "Macmini", "iMac"]
        let unknown = catalog.models.keys.filter { key in !prefixes.contains { key.hasPrefix($0) } }
        #expect(unknown.isEmpty, "\(unknown)")
        for (identifier, model) in catalog.models {
            if identifier.hasPrefix("iPhone") {
                #expect(model.name.hasPrefix("iPhone"), "\(identifier)")
            } else if identifier.hasPrefix("iPad") {
                #expect(model.name.hasPrefix("iPad"), "\(identifier)")
            } else {
                #expect(model.name.hasPrefix("Mac") || model.name.hasPrefix("iMac"), "\(identifier)")
            }
        }
    }

    /// 標準は機種名＋搭載メモリ。チップ・世代・画面の大きさを添える
    @Test
    func deviceLabelShowsModelAndMemory() {
        #expect(Self.iPhone17Pro.text(hidesModel: false) == "iPhone 17 Pro（12GB）")
        let macBookAir = ShareDeviceLabel(kind: .mac, nominalGigabytes: 24, model: DeviceModel(name: "MacBook Air", chip: "M5"))
        #expect(macBookAir.text(hidesModel: false) == "MacBook Air（M5・24GB）")
        let iPhoneSE = ShareDeviceLabel(kind: .iPhone, nominalGigabytes: 4, model: DeviceModel(name: "iPhone SE", generation: 3))
        #expect(iPhoneSE.text(hidesModel: false) == "iPhone SE（第3世代・4GB）")
        let iPadPro = ShareDeviceLabel(kind: .iPad, nominalGigabytes: 16, model: DeviceModel(name: "iPad Pro", inches: "13", chip: "M4"))
        #expect(iPadPro.text(hidesModel: false) == "iPad Pro 13インチ（M4・16GB）")
        // Mac は、同じ機種 ID に Pro と Max があるので、`machdep.cpu.brand_string` のチップを表より先に使う
        let macBookPro = ShareDeviceLabel(kind: .mac, nominalGigabytes: 48, model: DeviceModel(name: "MacBook Pro"), chipOverride: "M4 Max")
        #expect(macBookPro.text(hidesModel: false) == "MacBook Pro（M4 Max・48GB）")
        let mini = ShareDeviceLabel(
            kind: .mac,
            nominalGigabytes: 16,
            model: DeviceModel(name: "Mac mini", chip: "M2"),
            chipOverride: "M2 Pro"
        )
        #expect(mini.text(hidesModel: false) == "Mac mini（M2 Pro・16GB）")
    }

    /// 「機種名を隠す」と、対応表に無い機種は、端末の種類と搭載メモリの級だけにする
    @Test
    func hiddenOrUnknownModelShowsOnlyClass() {
        #expect(Self.iPhone17Pro.text(hidesModel: true) == "iPhone（12GB 級）")
        #expect(Self.iPhone17Pro.shortName(hidesModel: false) == "iPhone 17 Pro")
        #expect(Self.iPhone17Pro.shortName(hidesModel: true) == "iPhone")
        let unknownPad = ShareDeviceLabel(kind: .iPad, nominalGigabytes: 8, model: nil)
        #expect(unknownPad.text(hidesModel: false) == "iPad（8GB 級）")
        #expect(unknownPad.shortName(hidesModel: false) == "iPad")
        let unknownMac = ShareDeviceLabel(kind: .mac, nominalGigabytes: 24, model: nil, chipOverride: "M4")
        #expect(unknownMac.text(hidesModel: false) == "Mac（24GB 級）")
    }

    /// 今の端末の表示は、ランキングのクラスと同じ正式な容量の搭載メモリを使う
    @Test
    func currentDeviceUsesNominalMemory() {
        let current = ShareDeviceLabel.current
        #expect(current.kind == DeviceKind.current)
        #expect(current.nominalGigabytes == DeviceMemoryProfile.current.nominalGigabytes)
        #expect(current.text(hidesModel: true) == ShareDeviceLabel.classText(kind: current.kind, gigabytes: current.nominalGigabytes))
    }

    /// 「Apple M4 Max」から「M4 Max」を取り出す。Apple シリコンでなければ nil
    @Test
    func chipComesFromAppleSiliconBrand() {
        #expect(DeviceIdentifier.chip(fromBrand: "Apple M4 Max") == "M4 Max")
        #expect(DeviceIdentifier.chip(fromBrand: "Apple M1") == "M1")
        #expect(DeviceIdentifier.chip(fromBrand: "Intel(R) Core(TM) i7-8700B CPU @ 3.20GHz") == nil)
        #expect(DeviceIdentifier.chip(fromBrand: "Apple ") == nil)
        #expect(DeviceIdentifier.chip(fromBrand: nil) == nil)
    }

    /// 「機種名を隠す」は次回も使う。データの初期化で消える
    @Test
    func hidesDeviceModelPersistsAndResets() throws {
        let suiteName = "UncleRAMTests.share.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LocalStore(defaults: defaults)
        #expect(!store.hidesDeviceModelInShare)
        store.hidesDeviceModelInShare = true
        #expect(LocalStore(defaults: defaults).hidesDeviceModelInShare)

        store.resetAll()
        #expect(!store.hidesDeviceModelInShare)
        #expect(!LocalStore(defaults: defaults).hidesDeviceModelInShare)
    }

    // MARK: - 画像

    /// ImageRenderer で、4:5 は 1080×1350、9:16 は 1080×1920 の PNG を書き出す。
    /// 環境変数 `UNCLERAM_SHARE_IMAGE_DIR` があれば、目で確かめられるようそこに書き出す
    /// （xcodebuild では `TEST_RUNNER_UNCLERAM_SHARE_IMAGE_DIR=<フォルダ>` で渡す）
    @Test(arguments: ShareImageFormat.allCases)
    func renderedImageHasExpectedPixelSize(format: ShareImageFormat) throws {
        let summary = try Self.summary(Self.outcome(.delivered, donated: 2_410))
        let device = Self.iPhone17Pro.text(hidesModel: false)
        let content = TributeStatementContent(summary: summary, device: device, price: .japan, isMac: false)
        let rendered = try #require(ShareImageRenderer.render(format: format, content: content))
        #expect(rendered.cgImage.width == 1_080)
        #expect(rendered.cgImage.height == (format == .portrait ? 1_350 : 1_920))
        #expect(CGSize(width: rendered.cgImage.width, height: rendered.cgImage.height) == format.pixelSize)
        #expect(rendered.pngData.starts(with: [0x89, 0x50, 0x4E, 0x47]))

        if let directory = ProcessInfo.processInfo.environment["UNCLERAM_SHARE_IMAGE_DIR"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try rendered.pngData.write(to: folder.appendingPathComponent("statement-\(format.rawValue).png"))
            let collected = try Self.summary(Self.outcome(.collected, donated: 2_498))
            let collectedContent = TributeStatementContent(summary: collected, device: "iPhone（12GB 級）", price: .japan, isMac: false)
            let collectedImage = try #require(ShareImageRenderer.render(format: format, content: collectedContent))
            try collectedImage.pngData.write(to: folder.appendingPathComponent("statement-\(format.rawValue)-collected.png"))
        }
    }
}

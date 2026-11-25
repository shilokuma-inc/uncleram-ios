import SwiftUI

/// 明細書に載せるもの。シェアに載せてよい値（機種名・献上量・金額と、その元になる値）だけを持つ
nonisolated struct TributeStatementContent: Sendable, Equatable {
    let summary: ShareSummary
    /// 端末の表示（「iPhone 17 Pro（12GB）」、隠すときは「iPhone（12GB 級）」）
    let device: String
    let price: MacUpgradePrice
    /// Mac で遊んだか。iPhone・iPad は増設できないので、「Mac 換算」と添える
    let isMac: Bool

    /// 架空の「AI の学習」が 1 秒に使うメモリ（MB）。用途の秒数（「推定 0.0003 秒分」）はここから計算する架空の値で、
    /// デザインの例（4,210 MB で 0.0003 秒、21,480 MB で 0.0015 秒）に合わせた（docs/SPEC.md「世界観・キャラクター・文言」の用途のしょぼさ）
    static let trainingMegabytesPerSecond = 14_000_000.0

    /// 用途の秒数。小数 4 桁で 0 になるほど小さいときは、0 でない桁が出るまで（8 桁まで）伸ばす
    func usageSecondsText(locale: Locale = .current) -> String {
        let seconds = Double(summary.donatedMegabytes) / Self.trainingMegabytesPerSecond
        var digits = 4
        while digits < 8, seconds > 0, (seconds * pow(10, Double(digits))).rounded() == 0 {
            digits += 1
        }
        return seconds.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    /// 控除の「空きメモリ」（GB。小数 1 桁）
    func deductedGigabytesText(locale: Locale = .current) -> String {
        (Double(summary.donatedBytes) / Double(DeviceMemoryProfile.bytesPerGigabyte))
            .formatted(.number.precision(.fractionLength(1)).locale(locale))
    }

    /// Mac で増設したときの金額
    var upgradeAmountText: String {
        price.formatted(price.amount(for: summary.donatedBytes))
    }
}

/// 献上明細書（docs/design/Result.png の明細書の部分、横 2 列は MacResult.png）。シェア画像と同じ固定のレイアウトにする
/// （docs/SPEC.md「アクセシビリティ」。文字は Dynamic Type で大きくしない）。項目は 1 行ずつ VoiceOver で読める。
///
/// 速達便は 1 ラウンドなので、デザインの「称号」と「総スコア」は載せない。称号は定期便の累計で上がるので、称号を入れるとき（段取り 4）に足す
struct TributeStatement: View {
    let content: TributeStatementContent
    /// 支給と控除を横に並べる（4:5 の画像）。並べないときは縦に積む（9:16 の画像）
    var twoColumns = false

    private var summary: ShareSummary {
        content.summary
    }

    var body: some View {
        VStack(spacing: 0) {
            StatementBorder()
            VStack(alignment: .leading, spacing: 6) {
                header
                DashedRule()
                ledger
                DashedRule()
                totals
                DashedRule()
                footer
            }
            .padding(.horizontal, twoColumns ? 24 : 20)
            .padding(.vertical, 10)
            StatementBorder()
        }
        .padding(.vertical, 12)
        .doubleFrame()
        .foregroundStyle(Theme.navy)
        .accessibilityElement(children: .contain)
    }

    // MARK: - 見出し

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("献上明細書")
                    .font(Theme.mincho(28, .extraBold))
                    .tracking(28 * 0.22)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text("\(year) 年 \(month) 月分　\(modeName)　提供者 殿")
                    .font(Theme.mincho(12, .medium))
                    .foregroundStyle(Theme.subText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            CircleStamp(text: stamp, diameter: 70, angle: .degrees(-12))
                .padding(.top, 2)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(stamp))
        }
    }

    private var year: Text {
        Text(verbatim: "\(summary.year)").font(Theme.typewriter(12))
    }

    private var month: Text {
        Text(verbatim: "\(summary.month)").font(Theme.typewriter(12))
    }

    private var modeName: String {
        switch summary.mode {
        case .express:
            String(localized: "速達便")
        case let .daily(_, number):
            number.map { String(localized: "デイリー #\($0)") } ?? String(localized: "デイリー")
        }
    }

    private var stamp: LocalizedStringKey {
        switch summary.result {
        case .delivered:
            "納品済"
        case .collected:
            "回収済"
        case .audited:
            "監査済"
        }
    }

    // MARK: - 支給と控除

    @ViewBuilder private var ledger: some View {
        if twoColumns {
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) { payments }
                VStack(alignment: .leading, spacing: 6) { deductions }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                payments
                deductions
            }
        }
    }

    @ViewBuilder private var payments: some View {
        sectionLabel("支給")
        row("感謝の言葉") {
            Text("\(Text(verbatim: "1").font(Theme.typewriter(14))) 式")
                .font(Theme.mincho(14))
        }
        // デザインでは控除の欄にあるが、手当は支給なので支給に置く（称号の行の代わり）
        row("ニアミス手当") {
            if summary.nearMissMultiplier > 1 {
                Text(verbatim: "×\(Self.multiplierText(summary.nearMissMultiplier))").font(Theme.typewriter(14))
            } else {
                Text("なし").font(Theme.mincho(14))
            }
        }
    }

    @ViewBuilder private var deductions: some View {
        sectionLabel("控除")
        row("空きメモリ") {
            Text(verbatim: "\(content.deductedGigabytesText()) GB").font(Theme.typewriter(14))
        }
        row("回収") {
            if summary.isCollected {
                Text("\(Text(verbatim: "\(content.deductedGigabytesText()) GB").font(Theme.typewriter(14)))（全額）")
                    .font(Theme.mincho(14))
            } else {
                Text("なし").font(Theme.mincho(14))
            }
        }
    }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(Theme.mincho(12, .extraBold))
            .tracking(12 * 0.3)
            .foregroundStyle(Theme.red)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - 合計と金額

    private var totals: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("献上量", labelFont: Theme.mincho(15, .extraBold)) {
                Text(verbatim: "\(Formatters.integer(Int(summary.donatedMegabytes))) MB").font(Theme.display(28))
            }
            row("スコア", labelFont: Theme.mincho(15, .extraBold)) {
                Text(verbatim: "\(Formatters.integer(summary.score)) pt")
                    .font(Theme.display(20))
                    .foregroundStyle(Theme.red)
            }
            row("用途") {
                Text("AI の学習（推定 \(Text(verbatim: content.usageSecondsText()).font(Theme.typewriter(14))) 秒分）")
                    .font(Theme.mincho(15, .medium))
            }
            row("Mac で増設すると", labelFont: Theme.mincho(14, .medium)) {
                Text("\(Text(verbatim: content.upgradeAmountText).font(Theme.display(18))) 相当")
                    .font(Theme.mincho(14, .medium))
            }
            row("\(Client.allocateCorp.name)の買取額", labelFont: Theme.mincho(14, .extraBold)) {
                Text(verbatim: content.price.formatted(0))
                    .font(Theme.display(18))
                    .foregroundStyle(Theme.red)
            }
            // 換算額の根拠（公式ストアの単価・時点・税の扱い）は、明細書にも必ず出す（docs/SPEC.md「金額の表示」の 1.1.6）
            Text(priceNote)
                .font(Theme.mincho(11, .medium))
                .lineSpacing(3)
                .foregroundStyle(Theme.subText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var priceNote: String {
        let difference = String(localized: "差額 \(content.upgradeAmountText) は「感謝の言葉 1 式」でお支払い済み。")
        let unit = "\(content.price.formattedPricePerGigabyte)\(content.price.note)"
        let basis = content.isMac
            ? String(localized: "公式ストアの増設価格 1GB \(unit)で換算")
            : String(localized: "※ 増設できない端末のため、公式ストアの増設価格 1GB \(unit)で Mac 換算")
        return difference + (content.isMac ? "" : "\n") + basis
    }

    // MARK: - 端末と発行

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: content.device)
                    .font(Theme.mincho(12, .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(verbatim: "Uncle RAM · #UncleRAM")
                    .font(Theme.typewriter(12))
                    .lineLimit(1)
                    .accessibilityHidden(true)
            }
            Text("発行　\(Client.allocateCorp.name) 経理部　／　承認　マロック会長")
                .font(Theme.mincho(12, .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.subText)
    }

    // MARK: - 部品

    /// 左に項目名、右に値の 1 行。VoiceOver では 1 つの項目として読む
    private func row(
        _ title: LocalizedStringKey,
        labelFont: Font = Theme.mincho(15, .medium),
        @ViewBuilder value: () -> some View
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(labelFont)
                .lineLimit(1)
            Spacer(minLength: 4)
            value()
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    static func multiplierText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// 明細書の上下の飾り罫（デザインの orn-b）
private struct StatementBorder: View {
    var body: some View {
        Canvas { context, size in
            let image = context.resolve(Image(.borderB))
            let natural = image.size
            guard natural.height > 0 else {
                return
            }
            let width = natural.width * size.height / natural.height
            // デザインと同じく、真ん中から左右に並べる
            var x = (size.width - width) / 2
            while x > 0 {
                x -= width
            }
            while x < size.width {
                context.draw(image, in: CGRect(x: x, y: 0, width: width, height: size.height))
                x += width
            }
        }
        .frame(height: 13)
        .clipped()
        .padding(.horizontal, 14)
        .accessibilityHidden(true)
    }
}

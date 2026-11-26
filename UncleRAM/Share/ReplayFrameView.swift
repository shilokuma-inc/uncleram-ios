import SwiftUI

/// リプレイ動画の 1 コマ（縦型 9:16、432 × 768pt を 2.5 倍した 1080 × 1920）。ラウンドの画面の部品（会長の欄・献上量のゲージ・
/// 回収飛行船・長押しのボタン・警告のノイズ）を、記録から作った `ReplayFrame` のとおりに描く。最後は明細書と「#UncleRAM」に移る。
///
/// 動画は紙と網点の絵だけで描き、OS の画面（アラート・ホーム画面・ステータスバー）には似せない
struct ReplayVideoFrame: View {
    static let format = ShareImageFormat.story

    let script: ReplayScript
    let frame: ReplayFrame
    /// 献上の部分の速さ（「REPLAY ×1.5」）
    let speed: Double
    /// 最後に出す明細書
    let content: TributeStatementContent

    var body: some View {
        ZStack {
            if frame.endCardOpacity < 1 {
                ReplayRoundFrame(script: script, frame: frame, speed: speed)
            }
            if frame.endCardOpacity > 0 {
                ReplayEndCard(content: content)
                    .opacity(frame.endCardOpacity)
            }
        }
        .frame(width: Self.format.canvasSize.width, height: Self.format.canvasSize.height)
        .clipped()
        // 動画は固定のレイアウトにする（文字の大きさの設定で崩れないように）
        .environment(\.dynamicTypeSize, .large)
        .environment(\.colorScheme, .light)
    }
}

/// ラウンドの場面（押す前・献上中・結果）
private struct ReplayRoundFrame: View {
    let script: ReplayScript
    let frame: ReplayFrame
    let speed: Double

    private var isResult: Bool {
        frame.scene == .result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Ornament(height: 12)
            ChairmanPanel(
                line: ReplayChairman.line(frame: frame, script: script),
                stage: ReplayChairman.displayedStage(frame: frame),
                leaning: ReplayChairman.isLeaning(frame: frame)
            )
            readout
            stageArea
            footer
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(width: ReplayVideoFrame.format.canvasSize.width, height: ReplayVideoFrame.format.canvasSize.height)
        .background { PaperBackground() }
        .overlay {
            if let noise = frame.noiseFrame {
                // 練習ラウンドでは兆しを大きく出す（ラウンドの画面と同じ）
                InkNoise(intensity: script.isPractice ? 1.6 : 1, frame: UInt64(noise))
            }
        }
        .foregroundStyle(Theme.navy)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.typewriter(12))
                    .tracking(1)
                    .foregroundStyle(Theme.subText)
                Text("取引先: \(Client.allocateCorp.name)")
                    .font(Theme.mincho(15))
            }
            Spacer()
            Text(verbatim: "REPLAY ×\(speed.formatted(.number.precision(.fractionLength(0...1))))")
                .font(Theme.display(13))
                .tracking(1.2)
                .foregroundStyle(Theme.red)
        }
    }

    private var title: LocalizedStringKey {
        switch script.title {
        case let .express(practice):
            practice ? "練習 · 速達便" : "速達便"
        case let .daily(number):
            if let number {
                "デイリー #\(number)"
            } else {
                "デイリー"
            }
        }
    }

    // MARK: - 献上量

    private var readout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(readoutLabel)
                .font(Theme.typewriter(isResult ? 12 : 11))
                .foregroundStyle(Theme.red)
                .lineLimit(1)
            if let squares = frame.squares {
                ReplaySquares(filled: squares, burst: isResult && script.result == .collected)
            } else if let bytes = frame.donatedBytes {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: Formatters.megabytes(bytes))
                        .font(Theme.display(62))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(verbatim: "MB")
                        .font(Theme.display(22))
                }
            }
            gauge
            footnote
        }
    }

    private var readoutLabel: LocalizedStringKey {
        guard isResult else {
            return "献上中（実測）"
        }
        return script.revealedLine == nil ? "今回の献上（回収ラインは明日お知らせします）" : "今回の献上と回収ライン"
    }

    @ViewBuilder private var gauge: some View {
        if isResult, let line = script.revealedLine {
            // 速達便は、結果の画面と同じく回収ラインと離した位置を並べて明かす
            RevealGauge(released: frame.fill, line: line)
                .padding(.top, 30)
                .padding(.bottom, 44)
        } else {
            DonationGauge(fill: frame.fill, safetyLine: script.safetyLineFill, height: 24, client: .allocateCorp)
        }
    }

    @ViewBuilder private var footnote: some View {
        if isResult {
            HStack(alignment: .center) {
                if let line = script.revealedLine {
                    gapText(line: line)
                }
                Spacer(minLength: 0)
                if script.nearMissMultiplier > 1 {
                    BoxStamp(caption: "ニアミス", value: "×\(TributeStatement.multiplierText(script.nearMissMultiplier))")
                        .opacity(frame.stampProgress)
                }
            }
            .frame(minHeight: 60)
            .padding(.top, script.revealedLine == nil ? 26 : 0)
        } else {
            HStack(spacing: 12) {
                Text("回収ライン: ？？？")
                if let budget = script.budgetBytes {
                    Text("枠 \(Formatters.megabytes(budget)) MB")
                }
            }
            .font(Theme.mincho(12, .medium))
            .foregroundStyle(Theme.subText)
            .padding(.top, 14)
        }
    }

    /// 「あと 2%！」「3% 越えた」（結果の画面と同じ）
    @ViewBuilder private func gapText(line: Double) -> some View {
        let gap = Formatters.percent(abs(line - frame.fill))
        if script.result == .collected {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "\(gap)%")
                    .font(Theme.display(40))
                    .foregroundStyle(Theme.red)
                Text("越えた")
                    .font(Theme.mincho(15, .extraBold))
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("あと")
                    .font(Theme.mincho(15, .extraBold))
                Text(verbatim: "\(gap)%")
                    .font(Theme.display(40))
                    .foregroundStyle(Theme.red)
                Text(verbatim: "！")
                    .font(Theme.mincho(15, .extraBold))
            }
        }
    }

    // MARK: - ボタンと回収飛行船

    private var stageArea: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if isResult {
                    resultStamp
                } else {
                    HoldButtonFace(holding: frame.scene == .donating, diameter: 206)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 結果では回収飛行船を下げて、判子と「全メモリ回収」を見せる
            if !isResult {
                Airship(
                    stage: frame.stage,
                    emphasized: script.isPractice,
                    scaleOverride: frame.airshipScale
                )
                .padding(.top, 2)
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// 結果の判子。紙に押しつけるように、大きく浮いたところから縮めて出す
    private var resultStamp: some View {
        let press = frame.stampProgress
        return VStack(spacing: 10) {
            if script.result == .collected {
                Text("全メモリ回収")
                    .font(Theme.heading(42))
                    .foregroundStyle(Theme.red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            CircleStamp(text: stampText, diameter: 150, angle: .degrees(-12))
        }
        .scaleEffect(1.5 - 0.5 * press)
        .opacity(press)
    }

    private var stampText: LocalizedStringKey {
        switch script.result {
        case .delivered:
            "納品"
        case .collected:
            script.isEarlyCollection ? "抜き打ち\n回収" : "回収"
        case .audited:
            "監査"
        }
    }

    private var footer: some View {
        HStack {
            Text(verbatim: "Uncle RAM")
            Spacer()
            Text(verbatim: "#UncleRAM")
        }
        .font(Theme.typewriter(13))
        .foregroundStyle(Theme.subText)
    }
}

/// デイリーの 10 マス（文字の共有の 🟥⬜ と同じ数）。回収されたら、最後に塗ったマスを 💥 にする
private struct ReplaySquares: View {
    let filled: Int
    let burst: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<ShareSummary.squareCount, id: \.self) { index in
                ZStack {
                    if burst, index == filled - 1 {
                        InkSurface()
                        Text(verbatim: "💥")
                            .font(.system(size: 24))
                    } else if index < filled {
                        InkSurface(color: Theme.red)
                    } else {
                        InkSurface()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
                .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1.5) }
            }
        }
        .padding(.vertical, 6)
    }
}

/// 最後の明細書（シェア画像の 9:16 と同じものを少し縮める）と、その下の「#UncleRAM」
struct ReplayEndCard: View {
    static let statementScale = 0.9

    let content: TributeStatementContent

    var body: some View {
        let size = ReplayVideoFrame.format.canvasSize
        VStack(spacing: 4) {
            ShareImageCanvas(format: .story, content: content, showsPaper: false)
                .scaleEffect(Self.statementScale, anchor: .top)
                .frame(width: size.width, height: size.height * Self.statementScale, alignment: .top)
            Text(verbatim: "#UncleRAM")
                .font(Theme.display(28))
                .tracking(1.5)
                .foregroundStyle(Theme.red)
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height)
        .background { PaperBackground() }
    }
}

/// 会長の台詞（ラウンドの画面の `ChairmanLines` と、結果の画面の台詞に合わせる）
enum ReplayChairman {
    static func line(frame: ReplayFrame, script: ReplayScript) -> LocalizedStringKey {
        switch frame.scene {
        case .waiting:
            "その RAM、ほとんど\n使われていませんよね？"
        case .result:
            resultLine(script)
        case .donating:
            donatingLine(frame)
        }
    }

    /// 結果の画面（`ResultView`）の台詞
    private static func resultLine(_ script: ReplayScript) -> LocalizedStringKey {
        switch script.result {
        case .collected:
            "ご提供いただいた全メモリは、当社が責任をもって有効活用いたします。"
        case .audited:
            "監査が入りました。"
        case .delivered:
            script.revealedLine == nil ? "ラインは明日、お教えしましょう" : "ラインはここだった"
        }
    }

    private static func donatingLine(_ frame: ReplayFrame) -> LocalizedStringKey {
        switch frame.bluff {
        case .showing:
            return "……ほう。\nずいぶん気前がいい。"
        case .grinning:
            return "……なんてな。"
        case .none:
            break
        }
        switch frame.stage {
        case .none:
            return "効率化へのご協力、\n心より感謝申し上げます。"
        case .sign:
            return "……ほう。\nずいぶん気前がいい。"
        case .approach, .warning:
            return "あと少しだけ、\nあと少しだけですので。"
        }
    }

    static func isLeaning(frame: ReplayFrame) -> Bool {
        guard frame.scene == .donating else {
            return false
        }
        return frame.bluff == .showing || (frame.bluff == .none && frame.stage >= .sign)
    }

    /// はったりのときは、ヒントの欄にも偽の気配を出す
    static func displayedStage(frame: ReplayFrame) -> RoundPlan.HintStage {
        frame.bluff == .showing ? .sign : frame.stage
    }
}

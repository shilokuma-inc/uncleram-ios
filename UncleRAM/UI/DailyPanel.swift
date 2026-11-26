import SwiftUI

/// タイトルの「本日のデイリー」の欄（docs/design/MacMain.png の右上の赤い欄）。2026-11-26 にユーザーが決めた中身:
/// 通し番号・「全員同じ条件」・日付に合わせた一言・締め切り（世界標準時の 0 時）までの時間・「挑戦する」・昨日の回収ライン。
/// 1 日 1 回なので、挑戦したあとは「挑戦する」の代わりに、その日の記録を出す
struct DailyPanel: View {
    let record: DailyRecord?
    let onStart: (DailyChallenge) -> Void
    var compact = false

    var body: some View {
        // 締め切りまでの時間を 1 秒ごとに進め、世界標準時の 0 時を越えたら次の日のデイリーに替える
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let challenge = DailyChallenge.today(now: context.date)
            content(challenge: challenge, now: context.date)
        }
    }

    private func content(challenge: DailyChallenge, now: Date) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            Text(Self.heading(challenge))
                .scaledFont(.mincho(12))
                .tracking(1)
            Text(Self.flavor(for: challenge.day))
                .scaledFont(.mincho(compact ? 15 : 17))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline) {
                Text("締め切りまで")
                    .scaledFont(.mincho(12))
                Spacer()
                Text(verbatim: Self.countdown(until: challenge.day.start.addingTimeInterval(86_400), now: now))
                    .scaledFont(.typewriter(14))
                    .monospacedDigit()
            }
            if let record, record.isPlayed(on: challenge.day) {
                Text(Self.playedText(record))
                    .scaledFont(.mincho(14))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 10 : 12)
                    .overlay { Rectangle().strokeBorder(Theme.lightPaper.opacity(0.7), lineWidth: 1) }
            } else {
                Button {
                    onStart(challenge)
                } label: {
                    Text("挑戦する")
                        .scaledFont(.mincho(15, .extraBold))
                        .tracking(2)
                        .foregroundStyle(Theme.navy)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 10 : 12)
                        .background { InkSurface() }
                        .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1).padding(4) }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("昨日の回収ライン \(Formatters.percent(Self.yesterdayLine(before: challenge.day)))%")
                .scaledFont(.mincho(12, .medium))
                .opacity(0.85)
        }
        .foregroundStyle(Theme.lightPaper)
        .padding(.horizontal, compact ? 16 : 20)
        .padding(.vertical, compact ? 14 : 18)
        .background { InkSurface(color: Theme.red) }
        .padding(5)
        .overlay { Rectangle().strokeBorder(Theme.navy, lineWidth: 1.5) }
        .accessibilityElement(children: .contain)
    }

    /// 「本日のデイリー #12 · 全員同じ条件」。通し番号の起点（仮に 2026-12-01）より前は番号を省く
    static func heading(_ challenge: DailyChallenge) -> LocalizedStringKey {
        if let number = challenge.number {
            "本日のデイリー #\(number) · 全員同じ条件"
        } else {
            "本日のデイリー · 全員同じ条件"
        }
    }

    /// 日付に合わせた一言。月末（その月の最後の日、世界標準時）は「月末につき、ノルマ厳しめ」（文言だけで、回収ラインは変えない）
    static func flavor(for day: DailyDay) -> LocalizedStringKey {
        let next = DailyDay(daysSince1970: day.daysSince1970 + 1)
        return next.components.month != day.components.month ? "月末につき、ノルマ厳しめ" : "本日も全員、同じ回収ラインです"
    }

    /// 「06:41:12」
    static func countdown(until deadline: Date, now: Date) -> String {
        let seconds = max(0, Int(deadline.timeIntervalSince(now)))
        let parts = [seconds / 3_600, seconds % 3_600 / 60, seconds % 60]
        return parts.map { $0 < 10 ? "0\($0)" : "\($0)" }.joined(separator: ":")
    }

    /// 昨日のデイリーの回収ライン（枠に対する割合。安全ラインがふつう（枠の 85%）の端末の値）
    static func yesterdayLine(before day: DailyDay) -> Double {
        DailyChallenge(day: DailyDay(daysSince1970: day.daysSince1970 - 1)).makePlan().collectionLine
    }

    /// 挑戦したあとに出す、その日の記録
    static func playedText(_ record: DailyRecord) -> LocalizedStringKey {
        switch record.result {
        case .delivered, .audited:
            "本日は献上済み · \(Formatters.integer(record.score ?? 0)) pt"
        case .collected:
            "本日は回収されました"
        case .voided:
            "本日は無効になりました"
        case .started:
            "本日は挑戦済み"
        }
    }
}

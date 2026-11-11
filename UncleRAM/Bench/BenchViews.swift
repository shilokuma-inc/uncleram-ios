import SwiftUI

/// 計測を始めるボタン（Debug ビルドと TestFlight のときだけ出す）
struct BenchButton: View {
    let bench: BenchRunner

    var body: some View {
        if bench.isAvailable, !bench.isRunning {
            Menu {
                Button("100 ラウンド（全体を乱数で埋める）") {
                    bench.start(rounds: 100, fillMode: .full)
                }
                Button("100 ラウンド（ページごとに少しだけ書く）") {
                    bench.start(rounds: 100, fillMode: .sparse)
                }
                Button("10 ラウンド（全体を乱数で埋める）") {
                    bench.start(rounds: 10, fillMode: .full)
                }
            } label: {
                Text("計測")
                    .font(Theme.typewriter(12))
                    .foregroundStyle(Theme.subText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay { Rectangle().strokeBorder(Theme.subText, lineWidth: 1) }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
        }
    }
}

/// 計測中の進み具合と、終わったときの結果
struct BenchStatusBar: View {
    let bench: BenchRunner

    var body: some View {
        if bench.isRunning {
            HStack {
                Text(verbatim: "BENCH \(bench.progress) / \(bench.plannedRounds)")
                    .font(Theme.typewriter(13))
                Spacer()
                Button("中止") { bench.cancel() }
                    .buttonStyle(.plain)
                    .font(Theme.mincho(13))
            }
            .foregroundStyle(Theme.lightPaper)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.navy.opacity(0.88))
        } else if let summary = bench.summary {
            BenchSummaryView(summary: summary, savedURL: bench.savedURL, json: bench.summaryJSON()) {
                bench.dismissSummary()
            }
        }
    }
}

struct BenchSummaryView: View {
    let summary: BenchRunner.Summary
    let savedURL: URL?
    let json: String?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "計測の結果（\(summary.fillMode.rawValue)）")
                .font(Theme.mincho(15))
            Group {
                line("ラウンド", "\(summary.completedRounds) / \(summary.plannedRounds)")
                line("解放の最大 / 95%", "\(format(summary.maxReleaseMilliseconds)) / \(format(summary.p95ReleaseMilliseconds)) ms")
                line("200ms を越えた解放", "\(summary.releasesOver200Milliseconds) 回")
                line("落ちたフレーム（献上中）", droppedFrames)
                line("落ちたフレーム（解放の間）", releaseDroppedFrames)
                line("使用量 ÷ 献上量（最小）", summary.minimumFootprintPerDonated.map { format($0, digits: 3) } ?? "-")
                line("スワップ", swap)
                line("host_statistics64", summary.hostStatisticsAvailable ? "取れる" : "取れない")
                line("メモリ警告", "\(summary.memoryWarnings) 回")
                line("終わり方", summary.outcomes.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: " / "))
            }
            .font(Theme.typewriter(12))
            if let savedURL {
                Text(verbatim: savedURL.lastPathComponent)
                    .font(Theme.typewriter(10))
                    .foregroundStyle(Theme.subText)
                    .textSelection(.enabled)
            }
            HStack {
                if let json {
                    ShareLink(item: json) {
                        Text("結果を共有")
                    }
                }
                Spacer()
                Button("閉じる", action: onClose)
            }
            .buttonStyle(.plain)
            .font(Theme.mincho(14))
            .foregroundStyle(Theme.red)
        }
        .foregroundStyle(Theme.navy)
        .padding(16)
        .frame(maxWidth: 520, alignment: .leading)
        .doubleFrame()
        .padding(12)
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: title)
            Spacer()
            Text(verbatim: value)
                .multilineTextAlignment(.trailing)
        }
    }

    private var droppedFrames: String {
        "\(summary.droppedFrames) / \(summary.totalFrames)（最長 \(format(summary.worstFrameIntervalMilliseconds)) ms）"
    }

    private var releaseDroppedFrames: String {
        "\(summary.releaseDroppedFrames)（最長 \(format(summary.releaseWorstFrameIntervalMilliseconds)) ms）"
    }

    private var swap: String {
        let before = summary.swapBeforeMegabytes.map { format($0) } ?? "-"
        let max = summary.swapMaxMegabytes.map { format($0) } ?? "-"
        return "\(before) → 最大 \(max) MB"
    }

    private func format(_ value: Double, digits: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
}

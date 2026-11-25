import CryptoKit
import Foundation

/// デイリー（速達便の 1 日 1 回版）の、ある日の条件。全員が同じ条件で遊ぶ（docs/SPEC.md「速達便・デイリーの条件と乱数」）。
///
/// 日付から作った種の SplitMix64 で、アロケート社の `RoundPlan.make` を回す。乱数を使う順番が決まっているので、
/// 回収ライン（枠に対する割合）・ヒントの出る位置・はったりは、どの端末でも同じになる（MB は端末ごとに違う）。
/// ここは計算だけで、画面と、1 日 1 回を覚えておく保存は持たない。
nonisolated struct DailyChallenge: Sendable, Equatable {
    /// デイリーの式の版（docs/SPEC.md「式を変えるとき」）
    ///
    /// 式は、種の作り方と、種から条件を作るやり方（取引先と `RoundPlan.make` の乱数の使い方）の両方を指す。
    /// どちらを変えても同じ日のラインが変わるので、新しい版を足し、切り替える日からあとの日だけに使う。
    /// 過去の日（練習）は、その日に使っていた版で作り直す。
    enum Formula: Sendable, Equatable {
        /// 種は SHA-256("UncleRAM-daily-v1-" + 世界標準時の YYYYMMDD) の先頭 8 バイト。
        /// 条件はアロケート社の `RoundPlan.make`（乱数の順番: 早期回収かどうか → 回収ライン → ヒントの揺らぎ → はったり）
        case v1

        /// day に使う版。v2 を足すときは、切り替える日と比べて分ける（例: `day >= DailyDay(year: 2027, month: 4, day: 1) ? .v2 : .v1`）
        static func formula(for day: DailyDay) -> Formula {
            .v1
        }

        /// 種にする文字列の、日付の前に付ける文字
        var seedPrefix: String {
            switch self {
            case .v1:
                "UncleRAM-daily-v1-"
            }
        }

        /// day の種。SHA-256 の先頭 8 バイトを big endian（先頭のバイトを上位）で読む。
        /// 16 進で書いたハッシュの先頭 16 文字と同じ値になるので、ほかの言語やツールでも確かめやすい
        func seed(for day: DailyDay) -> UInt64 {
            let digest = SHA256.hash(data: Data((seedPrefix + day.yyyymmdd).utf8))
            return digest.prefix(8).reduce(0) { ($0 << 8) | UInt64($1) }
        }
    }

    /// その日のデイリーを、今どう扱うか
    enum Status: Sendable, Equatable {
        /// 今日のデイリー。1 日 1 回で、ランキングに送る。その日のうちは結果でラインの位置を明かさない
        case today
        /// 過去の日。ランキングに送らない「練習」として遊べる。結果でラインの位置を見せてよい
        case practice
        /// まだ来ていない日（日付を書き換えたリンクなど）。遊ばせない。先に遊べると、その日のラインが分かってしまう
        case upcoming

        /// ランキング（Game Center）に送るか
        var isRanked: Bool {
            self == .today
        }

        /// 結果で回収ラインの位置を見せてよいか（docs/SPEC.md「デイリーだけは明かさない」）
        var revealsCollectionLine: Bool {
            self == .practice
        }
    }

    /// 取引先。デイリーはアロケート社に固定し、取引先の倍率はかけない
    static let client = Client.allocateCorp

    /// 通し番号の起点（#1 の日、世界標準時）。公開日を #1 にするが、まだ決まっていないので、仮に 2026-12-01 にしている
    /// （2026-11-26 にユーザーが決定）。公開日が決まったら直す（docs/HANDOFF.md の段取り 5）
    static let firstDay = DailyDay(year: 2026, month: 12, day: 1)

    let day: DailyDay
    let formula: Formula
    /// この日の SplitMix64 の種
    let seed: UInt64

    init(day: DailyDay) {
        self.day = day
        formula = Formula.formula(for: day)
        seed = formula.seed(for: day)
    }

    /// 今日のデイリー。世界標準時の 0 時（日本時間 9 時）に次の日へ切り替わる
    static func today(now: Date = .now) -> DailyChallenge {
        DailyChallenge(day: DailyDay(containing: now))
    }

    /// 通し番号（`firstDay` が #1）。起点より前の日（公開前の TestFlight など）は nil
    var number: Int? {
        let offset = day.daysSince1970 - Self.firstDay.daysSince1970
        return offset >= 0 ? offset + 1 : nil
    }

    /// now の時点での扱い（今日・練習・まだ来ていない）
    func status(now: Date = .now) -> Status {
        let today = DailyDay(containing: now)
        if day == today {
            return .today
        }
        return day < today ? .practice : .upcoming
    }

    /// この日の乱数。`RoundEngine` に（取引先 `client` と一緒に）渡すと、最初のラウンドがこの日の条件になる。
    /// 振動の揺らぎを入れるときは、`RoundPlan.make` のあとに同じ乱数から引く（docs/SPEC.md「早期回収」の乱数の順番）
    func makeRandom() -> SplitMix64 {
        SplitMix64(seed: seed)
    }

    /// この日の条件（v1）。`RoundEngine` の最初のラウンドと同じものになる
    /// - Parameter safetyLine: その端末の安全ライン（枠に対する割合）。ふだんは 85% で、回収ラインは全員同じ。
    ///   枠が小さく安全ラインが手前になる端末だけ、回収ラインが「安全ライン − 枠の 5%」で頭打ちになる
    func makePlan(safetyLine: Double = SafetyLine.budgetRatio) -> RoundPlan {
        var random = makeRandom()
        return RoundPlan.make(client: Self.client, safetyLine: safetyLine, random: &random)
    }
}

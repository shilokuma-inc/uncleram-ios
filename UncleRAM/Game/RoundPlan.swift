import Foundation

/// 1 ラウンドの隠れた条件（回収ライン・ヒントの出る位置・はったり）。値はすべて枠に対する割合（0〜1）。
///
/// docs/SPEC.md「ゲーム性の見直し」の「早期回収」「ヒントの出方」に合わせる。
nonisolated struct RoundPlan: Sendable, Equatable {
    /// ヒントの段階。必ず 1 → 2 → 3 の順に出る
    enum HintStage: Int, Sendable, Comparable, CaseIterable {
        /// まだ何も出ていない
        case none = 0
        /// 1. 気配（会長の表情が変わる）
        case sign = 1
        /// 2. 接近（回収飛行船が近づく）
        case approach = 2
        /// 3. 警告（画面にノイズが走る）
        case warning = 3

        static func < (lhs: HintStage, rhs: HintStage) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// 早期回収のラウンドか（結果に「抜き打ち回収」の判子を押す）
    let isEarlyCollection: Bool
    /// 回収ライン。献上量がこれを越えると回収される
    let collectionLine: Double
    /// ヒントの 1〜3 段階が出る位置（昇順）
    let hintThresholds: [Double]
    /// はったり（偽の気配）を出す位置。出さないラウンドは nil
    let bluffAt: Double?

    /// ヒントの出る位置（回収ラインの手前）と揺らぎ
    static let hintOffsets: [(distance: Double, jitter: Double)] = [
        (0.15, 0.04),
        (0.08, 0.025),
        (0.02, 0.02)
    ]
    /// 揺らぎで順番が入れ替わるときに、後の段階をずらす幅
    static let minimumHintGap = 0.005
    /// はったりの出るラウンドの割合と、出る範囲
    static let bluffProbability = 0.15
    static let bluffRange: ClosedRange<Double> = 0.15...0.70
    /// 回収ラインを安全ラインからどれだけ手前に置くか
    static let marginBelowSafetyLine = 0.05

    /// - Parameters:
    ///   - client: 取引先
    ///   - safetyLine: このラウンドの安全ライン（枠に対する割合）。回収ラインは「安全ライン − 枠の 5%」を越えない
    ///   - random: 乱数。使う順番は「早期回収かどうか → 回収ライン → ヒントの揺らぎ → はったり」で固定する（デイリーで全員が同じになるように）
    static func make(client: Client, safetyLine: Double, random: inout SplitMix64) -> RoundPlan {
        let isEarly = random.chance(client.earlyCollectionProbability)
        let range = isEarly ? client.earlyLineRange : client.lineRange
        let ceiling = max(0.05, safetyLine - marginBelowSafetyLine)
        let line = min(random.uniform(range), ceiling)

        var thresholds: [Double] = []
        for offset in hintOffsets {
            var position = line - offset.distance + random.uniform(-offset.jitter...offset.jitter)
            if let previous = thresholds.last {
                position = max(position, previous + minimumHintGap)
            }
            thresholds.append(max(0, position))
        }
        // 警告がラインそのものを越えると、出た瞬間に回収されて合図にならないので、ラインの手前に収める
        thresholds[2] = min(thresholds[2], line - minimumHintGap / 2)

        let bluffAt: Double? = random.chance(bluffProbability) ? random.uniform(bluffRange) : nil
        return RoundPlan(isEarlyCollection: isEarly, collectionLine: line, hintThresholds: thresholds, bluffAt: bluffAt)
    }

    /// 献上量（割合）に対して、出ているヒントの段階
    func hintStage(at fill: Double) -> HintStage {
        let reached = hintThresholds.filter { fill >= $0 }.count
        return HintStage(rawValue: reached) ?? .warning
    }
}

import Foundation

/// 献上の速さ（枠に対する割合 / 秒）。docs/SPEC.md「ゲーム性の見直し」の「献上の速さ」。
///
/// - 枠の 30% までは 10%/秒（約 3 秒）
/// - 30% から先は 5%/秒で始め、1 秒ごとに 10% ずつ速くなり、上限は 9%/秒
/// - 速さは枠に対する位置と経過時間だけで決め、回収ラインには左右されない（速さからラインが読めないように）
nonisolated enum DonationSpeed {
    static let fastZoneEnd = 0.30
    static let fastZoneRate = 0.10
    static let slowZoneStartRate = 0.05
    static let slowZoneGrowthPerSecond = 1.10
    static let maximumRate = 0.09

    /// - Parameters:
    ///   - fill: いまの献上量（枠に対する割合）
    ///   - secondsInSlowZone: 30% を越えてからの秒数。まだ越えていなければ nil
    static func rate(fill: Double, secondsInSlowZone: Double?) -> Double {
        guard fill >= fastZoneEnd, let seconds = secondsInSlowZone else {
            return fastZoneRate
        }
        return min(maximumRate, slowZoneStartRate * pow(slowZoneGrowthPerSecond, seconds))
    }

    /// 0 から target まで押し続けたときの秒数（数値の確認用）
    static func secondsToReach(_ target: Double, step: Double = 0.001) -> Double {
        var fill = 0.0
        var elapsed = 0.0
        var slowZoneStart: Double?
        while fill < target {
            if fill >= fastZoneEnd, slowZoneStart == nil {
                slowZoneStart = elapsed
            }
            fill += rate(fill: fill, secondsInSlowZone: slowZoneStart.map { elapsed - $0 }) * step
            elapsed += step
        }
        return elapsed
    }
}

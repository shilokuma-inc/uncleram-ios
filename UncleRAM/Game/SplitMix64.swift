import Foundation

/// 自前の乱数（SplitMix64）。種が同じなら、どの端末でも同じ並びになる。
///
/// デイリーは全員が同じ条件で遊ぶため、OS の乱数ではなくこれを使う（docs/SPEC.md「速達便・デイリーの条件と乱数」）。
/// 乱数を使う順番は `RoundPlan.make` で固定している。
nonisolated struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    /// OS の乱数で種を決める（速達便）
    static func randomlySeeded() -> SplitMix64 {
        var system = SystemRandomNumberGenerator()
        return SplitMix64(seed: system.next())
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// 0 以上 1 未満の値（53 ビット）
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * 0x1.0p-53
    }

    /// range の中の一様な値
    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * nextUnit()
    }

    /// probability の確率で true
    mutating func chance(_ probability: Double) -> Bool {
        nextUnit() < probability
    }
}

import Foundation

/// 安全ライン。どんな場合も越えない止め。docs/SPEC.md「技術仕様」の「確保前の判定」。
///
/// 確保のたびに次の 2 つを両方とも確かめ、満たさなければ確保しない（その量で納品。回収ではない）:
/// 1. 献上量 + 確保する量 ≤ 枠 × 85%
/// 2. 今の残量 − 確保する量 ≥ max(枠 × 15%, 200MB)
nonisolated struct SafetyLine: Sendable, Equatable {
    static let budgetRatio = 0.85
    static let reserveRatio = 0.15
    static let minimumReserveBytes: UInt64 = 200 * 1024 * 1024
    /// 枠がこれより小さい端末では遊べないことを案内する
    static let minimumBudgetBytes: UInt64 = 600 * 1024 * 1024

    let budgetBytes: UInt64

    /// 1 つ目の条件の上限（枠 × 85%）
    var donationLimitBytes: UInt64 {
        UInt64(Double(budgetBytes) * Self.budgetRatio)
    }

    /// 2 つ目の条件で残す量（max(枠 × 15%, 200MB)）
    var reserveBytes: UInt64 {
        max(UInt64(Double(budgetBytes) * Self.reserveRatio), Self.minimumReserveBytes)
    }

    /// この枠で遊べるか
    var isPlayable: Bool {
        budgetBytes >= Self.minimumBudgetBytes
    }

    /// size を確保してよいか
    func allows(donated: UInt64, adding size: UInt64, available: UInt64) -> Bool {
        guard donated + size <= donationLimitBytes else {
            return false
        }
        return available >= size && available - size >= reserveBytes
    }

    /// ラウンド開始時の残量から見た、このラウンドの安全ライン（枠に対する割合）。
    /// 枠が小さく、2 つ目の条件が先に効く端末では 85% より手前になる。回収ラインはこれより枠の 5% 手前に置く
    func effectiveLine(available: UInt64) -> Double {
        guard budgetBytes > 0 else {
            return 0
        }
        let byReserve = available > reserveBytes ? available - reserveBytes : 0
        return Double(min(donationLimitBytes, byReserve)) / Double(budgetBytes)
    }
}

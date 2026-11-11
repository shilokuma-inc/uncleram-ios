import Foundation

/// ラウンドの終わり方と、スコアの計算。docs/SPEC.md「ゲームルール」「数値の初期値」「実装の詳細」。
nonisolated struct RoundOutcome: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        /// 離して納品した（安全ラインで止まったときも含む）
        case delivered
        /// 回収ラインを越えた。献上分はすべて失う
        case collected
        /// OS からメモリ警告が届いた。それまでの献上分は納品扱い
        case audited
        /// バックグラウンドへの移行や発熱で、ラウンドを無効にした。スコア 0
        case voided(VoidReason)
    }

    enum VoidReason: Sendable, Equatable {
        case background
        case thermal
    }

    let kind: Kind
    let plan: RoundPlan
    let budgetBytes: UInt64
    let donatedBytes: UInt64
    /// 安全ラインで止まったか（納品扱い）
    let stoppedAtSafetyLine: Bool

    /// 離した位置（枠に対する割合）
    var releasedFill: Double {
        guard budgetBytes > 0 else {
            return 0
        }
        return Double(donatedBytes) / Double(budgetBytes)
    }

    /// 離した位置と回収ラインの差（枠に対する割合）。越えていれば負
    var gapToLine: Double {
        plan.collectionLine - releasedFill
    }

    /// 納品が成功したか（回収・無効ではない）
    var isSuccessful: Bool {
        switch kind {
        case .delivered, .audited:
            true
        case .collected, .voided:
            false
        }
    }

    /// ニアミス倍率。納品が成功したときだけ効く。回収ラインとの差が枠の 3% 以内なら ×3、10% 以内なら ×1.5
    var nearMissMultiplier: Double {
        Self.nearMissMultiplier(gap: gapToLine, successful: isSuccessful)
    }

    static func nearMissMultiplier(gap: Double, successful: Bool) -> Double {
        guard successful, gap >= 0 else {
            return 1
        }
        if gap <= 0.03 {
            return 3
        }
        if gap <= 0.10 {
            return 1.5
        }
        return 1
    }

    /// 献上量（MB。1MB = 1,048,576 バイト）
    var donatedMegabytes: Double {
        Double(donatedBytes) / 1_048_576
    }

    /// スコア = 献上量（MB）× ニアミス倍率（速達便は取引先とラウンドの倍率をかけない）
    var score: Int {
        guard isSuccessful else {
            return 0
        }
        return Int((donatedMegabytes * nearMissMultiplier).rounded())
    }

    /// 腕前スコア = 回収ラインへの到達率（納品量 ÷ 回収ライン × 100）× ニアミス倍率。最大 300 pt。回収されたら 0
    var skillScore: Int {
        guard isSuccessful, plan.collectionLine > 0 else {
            return 0
        }
        let reach = min(1, releasedFill / plan.collectionLine) * 100
        return min(300, Int((reach * nearMissMultiplier).rounded()))
    }
}

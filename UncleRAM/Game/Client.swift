import Foundation

/// 取引先。回収ラインの散らばり方を決める（docs/SPEC.md「数値の初期値」「ゲーム性の見直し」）。
///
/// 値はすべて枠に対する割合（0〜1）。試作ではアロケート社だけを使う（速達便とデイリーはアロケート社に固定）。
nonisolated struct Client: Sendable, Equatable {
    /// 画面に出す名前
    let name: String
    /// 普段の回収ライン
    let lineRange: ClosedRange<Double>
    /// 早期回収になる確率
    let earlyCollectionProbability: Double
    /// 早期回収のときの回収ライン
    let earlyLineRange: ClosedRange<Double>

    /// アロケート社: 55〜80%。1 割のラウンドは早期回収で 30〜50%
    static let allocateCorp = Client(
        name: String(localized: "アロケート社"),
        lineRange: 0.55...0.80,
        earlyCollectionProbability: 0.10,
        earlyLineRange: 0.30...0.50
    )
}

import SwiftUI

extension EnvironmentValues {
    /// 今のラウンドの種類（速達便かデイリーか）。RoundScreen が入れ、見出しや結果の出し方を変える部品が読む
    @Entry var roundMode: RoundMode = .express
}

extension RoundMode {
    /// ラウンド画面の見出し（「速達便」「練習 · 速達便」「デイリー #12」）
    func title(practice: Bool) -> LocalizedStringKey {
        switch self {
        case .express:
            practice ? "練習 · 速達便" : "速達便"
        case let .daily(challenge):
            if let number = challenge.number {
                "デイリー #\(number)"
            } else {
                "デイリー"
            }
        }
    }

    /// 結果の見出し（「速達便 ・ 結果」「デイリー #12 ・ 結果」）
    var resultTitle: LocalizedStringKey {
        switch self {
        case .express:
            "速達便 ・ 結果"
        case let .daily(challenge):
            if let number = challenge.number {
                "デイリー #\(number) ・ 結果"
            } else {
                "デイリー ・ 結果"
            }
        }
    }

    /// 結果で回収ラインの位置を見せてよいか。デイリーは、その日のうちは見せない
    /// （全員が同じラインなので、ネタばれでほかの人の挑戦が崩れないように。docs/SPEC.md「説明なしで分かる UI」）
    func revealsCollectionLine(now: Date = .now) -> Bool {
        switch self {
        case .express:
            true
        case let .daily(challenge):
            challenge.status(now: now).revealsCollectionLine
        }
    }
}

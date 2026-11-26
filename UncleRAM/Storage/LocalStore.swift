import Foundation
import Observation

/// 端末の中だけに残す値。iCloud には入れない（docs/SPEC.md「初回起動と設定」）。
/// 進み具合のうち端末をまたいで共有するもの（クレジット・称号など）は、iCloud 同期と一緒に段取り 4 で別に持つ
@Observable
final class LocalStore {
    private enum Key {
        static let hasAcknowledgedSafetyNotice = "hasAcknowledgedSafetyNotice"
        static let tapToDonate = "tapToDonate"
        static let hasCompletedFirstRound = "hasCompletedFirstRound"
        static let seenTutorialBubbles = "seenTutorialBubbles"
        static let reducesCollectEffect = "reducesCollectEffect"
        static let hidesDeviceModelInShare = "hidesDeviceModelInShare"
        static let dailyRecord = "dailyRecord.v1"
        static let all = [
            hasAcknowledgedSafetyNotice,
            tapToDonate,
            hasCompletedFirstRound,
            seenTutorialBubbles,
            reducesCollectEffect,
            hidesDeviceModelInShare,
            dailyRecord
        ]
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// 初回の案内（本物のメモリを使うこと・裏のアプリが終了することがあること・端末が速くなるアプリではないこと）を閉じたか
    var hasAcknowledgedSafetyNotice: Bool {
        didSet { defaults.set(hasAcknowledgedSafetyNotice, forKey: Key.hasAcknowledgedSafetyNotice) }
    }

    /// 設定「タップで献上」。長押しの代わりに、1 回目のタップで献上を始め、もう一度タップすると納品する
    /// （Mac はクリックかスペースキーを 2 回。docs/SPEC.md「アクセシビリティ」）。ランキングは長押しと区別しない
    var tapToDonate: Bool {
        didSet { defaults.set(tapToDonate, forKey: Key.tapToDonate) }
    }

    /// 設定「回収演出を控えめにする」。オンなら、OS の「視差効果を減らす」と同じく、グリッチと揺れを止めて、飛行船の影と判子だけにする
    var reducesCollectEffect: Bool {
        didSet { defaults.set(reducesCollectEffect, forKey: Key.reducesCollectEffect) }
    }

    /// 最後に挑戦したデイリーの記録（1 日 1 回）。新しい日に挑戦すると上書きする
    var dailyRecord: DailyRecord? {
        didSet {
            if let dailyRecord, let data = try? JSONEncoder().encode(dailyRecord) {
                defaults.set(data, forKey: Key.dailyRecord)
            } else {
                defaults.removeObject(forKey: Key.dailyRecord)
            }
        }
    }

    /// 最初の 1 回（練習ラウンド）を終えたか。終えるまでは練習ラウンドにする（無効になったラウンドは数えない）
    var hasCompletedFirstRound: Bool {
        didSet { defaults.set(hasCompletedFirstRound, forKey: Key.hasCompletedFirstRound) }
    }

    /// 共有のプレビューの「機種名を隠す」。オンなら、シェアの端末の表示を「iPhone（12GB 級）」のように級だけにする。
    /// 選んだ内容は次に共有するときも使う（docs/SPEC.md「共有機能」の「端末の表示」）
    var hidesDeviceModelInShare: Bool {
        didSet { defaults.set(hidesDeviceModelInShare, forKey: Key.hidesDeviceModelInShare) }
    }

    /// 一度見せた吹き出し（`TutorialBubble` の rawValue）。設定「使い方をもう一度見る」で空にする
    var seenTutorialBubbles: Set<String> {
        didSet { defaults.set(seenTutorialBubbles.sorted(), forKey: Key.seenTutorialBubbles) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasAcknowledgedSafetyNotice = defaults.bool(forKey: Key.hasAcknowledgedSafetyNotice)
        tapToDonate = defaults.bool(forKey: Key.tapToDonate)
        reducesCollectEffect = defaults.bool(forKey: Key.reducesCollectEffect)
        dailyRecord = defaults.data(forKey: Key.dailyRecord).flatMap { try? JSONDecoder().decode(DailyRecord.self, from: $0) }
        hasCompletedFirstRound = defaults.bool(forKey: Key.hasCompletedFirstRound)
        seenTutorialBubbles = Set(defaults.stringArray(forKey: Key.seenTutorialBubbles) ?? [])
        hidesDeviceModelInShare = defaults.bool(forKey: Key.hidesDeviceModelInShare)
    }

    /// 設定「データの初期化」。端末の中の記録と設定をすべて消す（2026-11-26 にユーザーが決定）。
    /// ランキングの自分の最高記録と送り直し待ちのスコア（`UserDefaultsRankingStore`）も消す。
    /// Game Center に送った記録は消えない。値を足したら `Key.all` にも足す
    func resetAll() {
        for key in Key.all + UserDefaultsRankingStore.allKeys {
            defaults.removeObject(forKey: key)
        }
        hasAcknowledgedSafetyNotice = false
        tapToDonate = false
        reducesCollectEffect = false
        dailyRecord = nil
        hasCompletedFirstRound = false
        seenTutorialBubbles = []
        hidesDeviceModelInShare = false
    }
}

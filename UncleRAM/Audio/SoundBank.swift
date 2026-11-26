import AVFoundation
import os

/// 効果音（docs/SPEC.md「音と振動」）。ファイルは `Tools/sounds/make_sounds.py` が作る `UncleRAM/Sounds/<rawValue>.m4a`。
/// 出典とライセンスは、設定の「ライセンス」と docs/HANDOFF.md「素材の出典とライセンス」
nonisolated enum SoundEffect: String, CaseIterable, Sendable {
    /// 回収ライン接近（ヒントの 2 段階目）: 回収飛行船のプロペラ。ループで鳴らし、近づくにつれて大きくする
    case propeller
    /// 納品: 判子とタイプライターのベル
    case delivered
    /// 回収: 飛行船の汽笛（回収演出の始まり）
    case whistle
    /// リザルト: 明細書の印字（タイプライター）
    case receipt

    /// 音どうしの釣り合い（0〜1）。全体の大きさは `SoundBank.volume` で決める
    var mixLevel: Float {
        switch self {
        case .propeller: 0.8
        case .delivered: 1
        case .whistle: 0.7
        case .receipt: 0.6
        }
    }

    var loops: Bool {
        self == .propeller
    }
}

/// 効果音を鳴らす口。`RoundSounds` が使う。テストでは、呼ばれたことを記録するだけの偽物に差し替える
protocol SoundPlaying: AnyObject {
    /// `level`（0〜1。`SoundEffect.mixLevel` に対する割合）で、`delay` 秒あとに頭から鳴らす。
    /// `fadeIn` が 0 より大きいときは、無音からその秒数をかけて大きくする
    func play(_ effect: SoundEffect, level: Float, fadeIn: TimeInterval, delay: TimeInterval)
    /// 鳴っている音の大きさを、`duration` 秒かけて変える
    func setLevel(_ level: Float, of effect: SoundEffect, over duration: TimeInterval)
    /// `fadeOut` 秒かけて小さくしてから止める。`delay` を待っている（まだ鳴っていない）音も取り消す
    func stop(_ effect: SoundEffect, fadeOut: TimeInterval)
}

extension SoundPlaying {
    func stopAll() {
        for effect in SoundEffect.allCases {
            stop(effect, fadeOut: 0)
        }
    }
}

/// 効果音を AVAudioPlayer で鳴らす。音は起動の時に読み込む（`load()`）。
/// 圧縮したまま（AAC）読み込むので、メモリは音の分で 1MB に満たない
final class SoundBank: SoundPlaying {
    static let shared = SoundBank()

    /// 効果音全体の大きさ（0〜1）。設定の「効果音の音量」（段取り 4）を足すときは、ここに入れる
    var volume: Float = 1 {
        didSet {
            for (effect, player) in players where player.isPlaying {
                player.volume = (levels[effect] ?? 0) * effect.mixLevel * volume
            }
        }
    }

    private let bundle: Bundle
    private var players: [SoundEffect: AVAudioPlayer] = [:]
    /// 音ごとの今の `level`（`volume` を変えたときに、大きさを付け直すため）
    private var levels: [SoundEffect: Float] = [:]
    /// 止めるときのフェードを待つ間に、また鳴らし始めたら止めないための番号
    private var generations: [SoundEffect: Int] = [:]
    private let logger = Logger(subsystem: "jp.shilokuma.UncleRAM", category: "Sound")

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// 読み込めた音
    var loadedEffects: Set<SoundEffect> {
        Set(players.keys)
    }

    /// 音の長さ（秒）。読み込めていなければ nil
    func duration(of effect: SoundEffect) -> TimeInterval? {
        players[effect]?.duration
    }

    /// 起動の時に一度だけ呼ぶ。ラウンドの枠を量るより前に、音の分のメモリを使い終えておく（docs/SPEC.md「音と振動」）
    func load() {
        guard players.isEmpty else {
            return
        }
        #if os(iOS)
        // 消音スイッチに従い、ほかのアプリの音楽を止めない
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient)
        } catch {
            logger.error("AVAudioSession を ambient にできません: \(error.localizedDescription)")
        }
        #endif
        for effect in SoundEffect.allCases {
            guard let url = bundle.url(forResource: effect.rawValue, withExtension: "m4a") else {
                logger.error("効果音がありません: \(effect.rawValue)")
                continue
            }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = effect.loops ? -1 : 0
                player.prepareToPlay()
                players[effect] = player
            } catch {
                logger.error("効果音を読み込めません: \(effect.rawValue) \(error.localizedDescription)")
            }
        }
    }

    func play(_ effect: SoundEffect, level: Float, fadeIn: TimeInterval, delay: TimeInterval) {
        guard let player = players[effect] else {
            return
        }
        generations[effect, default: 0] += 1
        levels[effect] = level
        player.stop()
        player.currentTime = 0
        let target = level * effect.mixLevel * volume
        player.volume = fadeIn > 0 ? 0 : target
        let started = delay > 0 ? player.play(atTime: player.deviceCurrentTime + delay) : player.play()
        if fadeIn > 0 {
            player.setVolume(target, fadeDuration: fadeIn)
        }
        logger.debug("鳴らす: \(effect.rawValue) 大きさ \(target) 遅らせる \(delay) 秒 \(started ? "成功" : "失敗")")
    }

    func setLevel(_ level: Float, of effect: SoundEffect, over duration: TimeInterval) {
        guard let player = players[effect], player.isPlaying else {
            return
        }
        levels[effect] = level
        player.setVolume(level * effect.mixLevel * volume, fadeDuration: duration)
        logger.debug("大きさを変える: \(effect.rawValue) \(level)")
    }

    func stop(_ effect: SoundEffect, fadeOut: TimeInterval) {
        guard let player = players[effect] else {
            return
        }
        generations[effect, default: 0] += 1
        guard fadeOut > 0, player.isPlaying else {
            player.stop()
            return
        }
        let generation = generations[effect]
        player.setVolume(0, fadeDuration: fadeOut)
        logger.debug("止める: \(effect.rawValue) \(fadeOut) 秒で小さくする")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(fadeOut))
            guard let self, self.generations[effect] == generation else {
                return
            }
            self.players[effect]?.stop()
        }
    }
}

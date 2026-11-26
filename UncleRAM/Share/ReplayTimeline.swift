import Foundation

/// リプレイ動画に描いてよいもの（docs/SPEC.md「共有機能」の動画と「ネタバレを防ぐ」）。動画の絵と音は、これだけから作る。
///
/// - 速達便: 記録どおりの献上量（MB とゲージ）と枠を出し、最後に回収ラインと「あと ○%」を明かす（結果の画面と同じ）
/// - デイリー: 全員が同じ回収ラインなので、ラインの位置を割り出せるものを持たない。ゲージは公称の速さ（`DonationSpeed`）で動かして、
///   献上率を 10% 刻みで切り捨てた所（文字の共有の 10 マスと同じ）で止める。MB の数字と枠は出さない（伸び方の変わり目から枠が、
///   枠から回収ラインが割り出せるため）。ヒントの段階は 10% の区切りに寄せ、はったりは出さない
nonisolated struct ReplayScript: Sendable, Equatable {
    enum Title: Sendable, Equatable {
        case express(practice: Bool)
        case daily(number: Int?)
    }

    struct StageChange: Sendable, Equatable {
        /// 押し始めてからの秒数
        let time: Double
        let stage: RoundPlan.HintStage
    }

    struct BluffChange: Sendable, Equatable {
        let time: Double
        let bluff: RoundRecording.Bluff
    }

    let title: Title
    /// ゲージの動き（押し始めてからの秒数と、枠に対する割合）
    let points: [DonationCurve.Point]
    let stageChanges: [StageChange]
    let bluffChanges: [BluffChange]
    /// 押し始めてから離すまでの秒数
    let duration: Double
    let safetyLineFill: Double
    /// 枠。MB の数字と「枠 ○○ MB」を出すときだけ（デイリーは nil）
    let budgetBytes: UInt64?
    /// 献上量。MB の数字を出すときだけ（デイリーは nil）
    let donatedBytes: UInt64?
    /// 10 マスのうち、最後に埋めるマスの数（デイリー。速達便は nil）
    let squares: Int?
    let result: ShareSummary.Result
    /// 最後のゲージの量
    let finalFill: Double
    /// 最後に明かす回収ライン（速達便だけ。デイリーは nil）
    let revealedLine: Double?
    let nearMissMultiplier: Double
    let isEarlyCollection: Bool
    let isPractice: Bool

    init(replay: RoundReplay, mode: ShareSummary.Mode) {
        result = replay.result
        safetyLineFill = replay.recording.safetyLineFill
        nearMissMultiplier = replay.nearMissMultiplier
        isEarlyCollection = replay.isEarlyCollection
        isPractice = replay.recording.isPractice
        switch mode {
        case .express:
            title = .express(practice: replay.recording.isPractice)
            points = replay.recording.samples.map { DonationCurve.Point(time: Double($0.time), fill: Double($0.fill)) }
            stageChanges = replay.recording.stageChanges.map { StageChange(time: Double($0.time), stage: $0.stage) }
            bluffChanges = replay.recording.bluffChanges.map { BluffChange(time: Double($0.time), bluff: $0.bluff) }
            duration = replay.duration
            budgetBytes = replay.recording.budgetBytes
            donatedBytes = replay.donatedBytes
            squares = nil
            finalFill = replay.releasedFill
            revealedLine = replay.collectionLine
        case let .daily(_, number):
            title = .daily(number: number)
            let filled = ShareSummary.squares(for: replay.releasedFill)
            // 回収されたときは、文字の共有と同じく少なくとも 1 マス（最後のマスを 💥 にする）
            let shown = replay.result == .collected ? max(filled, 1) : filled
            let target = Double(shown) / Double(ShareSummary.squareCount)
            let curve = DonationCurve.nominal(until: target)
            points = curve.points
            stageChanges = Self.coarseStageChanges(replay: replay, squares: shown, curve: curve)
            bluffChanges = []
            duration = curve.duration
            budgetBytes = nil
            donatedBytes = nil
            squares = shown
            finalFill = target
            revealedLine = nil
        }
    }

    /// デイリーのヒントの段階。k マス目（k × 10%）に届いたときに、実際に k × 10% に届いた時点で出ていた段階を出す。
    /// 最後のマスより後に変わった段階は、離した時点（ゲージが止まった時点）で出す
    private static func coarseStageChanges(replay: RoundReplay, squares: Int, curve: DonationCurve) -> [StageChange] {
        var changes: [StageChange] = []
        var current = RoundPlan.HintStage.none
        func show(_ stage: RoundPlan.HintStage, at time: Double) {
            guard stage != current else {
                return
            }
            changes.append(StageChange(time: time, stage: stage))
            current = stage
        }
        if squares > 0 {
            for square in 1...squares {
                let boundary = Double(square) / Double(ShareSummary.squareCount)
                let stage = replay.time(reaching: boundary).map(replay.stage(at:)) ?? replay.stage(at: replay.duration)
                show(stage, at: curve.time(reaching: boundary))
            }
        }
        show(replay.stage(at: replay.duration), at: curve.duration)
        return changes
    }

    /// 押し始めてから `time` 秒のゲージの量（点の間は線でつなぐ）
    func fill(at time: Double) -> Double {
        guard let first = points.first else {
            return 0
        }
        guard time > first.time else {
            return first.fill
        }
        guard let index = points.firstIndex(where: { $0.time >= time }) else {
            return points[points.count - 1].fill
        }
        let before = points[index - 1]
        let after = points[index]
        let span = after.time - before.time
        let ratio = span > 0 ? (time - before.time) / span : 1
        return before.fill + (after.fill - before.fill) * ratio
    }

    func stage(at time: Double) -> RoundPlan.HintStage {
        stageChanges.last { $0.time <= time + 1e-9 }?.stage ?? .none
    }

    func bluff(at time: Double) -> RoundRecording.Bluff {
        bluffChanges.last { $0.time <= time + 1e-9 }?.bluff ?? .none
    }
}

/// リプレイ動画の 1 コマの中身
nonisolated struct ReplayFrame: Sendable, Equatable {
    enum Scene: Sendable, Equatable {
        /// 押す前
        case waiting
        /// 献上中
        case donating
        /// 結果（判子。速達便は回収ラインも明かす）
        case result
    }

    var scene: Scene
    /// ゲージの量（枠に対する割合）
    var fill: Double
    /// MB の数字（デイリーは nil）
    var donatedBytes: UInt64?
    /// 赤く塗る 10 マスの数（デイリー。速達便は nil）
    var squares: Int?
    var stage: RoundPlan.HintStage
    var bluff: RoundRecording.Bluff
    /// 回収飛行船の大きさ（段階が変わると、0.6 秒かけて変わる）
    var airshipScale: Double
    /// 警告のノイズの模様の番号。ノイズを出さないときは nil
    var noiseFrame: Int?
    /// 結果の判子を押す動き（0 → 1）
    var stampProgress: Double
    /// 最後の明細書の濃さ（0 → 1）
    var endCardOpacity: Double
}

/// 動画に入れる効果音の 1 つ
nonisolated struct ReplaySoundCue: Sendable, Equatable {
    struct LevelChange: Sendable, Equatable {
        let time: Double
        let level: Float
        let duration: Double
    }

    let effect: SoundEffect
    /// 動画の頭からの秒数
    let start: Double
    /// `SoundEffect.mixLevel` に対する割合
    var level: Float = 1
    var fadeIn: Double = 0
    /// ループの音を止める時刻。nil なら 1 回鳴らしきる
    var stop: Double?
    var fadeOut: Double = 0
    var levelChange: LevelChange?
}

/// リプレイ動画の時間割（docs/SPEC.md「共有機能」の動画: 縦型 9:16、約 10 秒）。
///
/// 押す前 0.6 秒 → 献上（記録どおりの動きを、少し速めて見せる）→ 結果 1.6 秒 → 明細書と「#UncleRAM」2 秒。
/// 献上の部分は、少なくとも 1.25 倍に速め、6 秒より長いラウンドは 6 秒に収まるまで速める（ふつうのラウンドは 3〜11 秒なので、
/// 動画は 5〜10 秒ほど。献上の速さが頭打ちになる大きい Mac で長くなったラウンドも、10 秒ほどに収まる）
nonisolated struct ReplayTimeline: Sendable {
    static let framesPerSecond = 30
    static let introDuration = 0.6
    static let minimumSpeed = 1.25
    static let targetReplayDuration = 6.0
    static let resultDuration = 1.6
    static let endCardDuration = 2.0
    static let crossfadeDuration = 0.3
    /// 回収飛行船の大きさが変わる秒数（`Airship` のアニメーションと同じ）
    static let airshipTransition = 0.6
    static let stampPressDuration = 0.2
    /// 明細書が出てから印字の音を鳴らすまで
    static let receiptDelay = 0.1

    let script: ReplayScript
    /// 献上の部分の速さ（倍）
    let speed: Double

    init(script: ReplayScript) {
        self.script = script
        speed = Self.speed(forDuration: script.duration)
    }

    static func speed(forDuration duration: Double) -> Double {
        max(minimumSpeed, duration / targetReplayDuration)
    }

    var replayDuration: Double {
        script.duration / speed
    }

    var resultStart: Double {
        Self.introDuration + replayDuration
    }

    var endCardStart: Double {
        resultStart + Self.resultDuration
    }

    var totalDuration: Double {
        endCardStart + Self.endCardDuration
    }

    var frameCount: Int {
        Int((totalDuration * Double(Self.framesPerSecond)).rounded(.up))
    }

    /// ラウンドの時刻（押し始めてからの秒数）が、動画のどこに来るか
    func videoTime(ofRoundTime time: Double) -> Double {
        Self.introDuration + time / speed
    }

    func frame(at index: Int) -> ReplayFrame {
        let time = Double(index) / Double(Self.framesPerSecond)
        if time < Self.introDuration {
            return frame(scene: .waiting, roundTime: 0, index: index, videoTime: time)
        }
        if time < resultStart {
            return frame(scene: .donating, roundTime: (time - Self.introDuration) * speed, index: index, videoTime: time)
        }
        return frame(scene: .result, roundTime: script.duration, index: index, videoTime: time)
    }

    private func frame(scene: ReplayFrame.Scene, roundTime: Double, index: Int, videoTime: Double) -> ReplayFrame {
        let fill = scene == .result ? script.finalFill : script.fill(at: roundTime)
        let stage = scene == .waiting ? .none : script.stage(at: roundTime)
        let donatedBytes: UInt64? = switch scene {
        case .waiting: script.budgetBytes.map { _ in 0 }
        case .donating: script.budgetBytes.map { UInt64(Double($0) * fill) }
        case .result: script.donatedBytes
        }
        let squares: Int? = script.squares.map { shown in
            min(shown, ShareSummary.squares(for: fill))
        }
        return ReplayFrame(
            scene: scene,
            fill: fill,
            donatedBytes: donatedBytes,
            squares: squares,
            stage: stage,
            bluff: scene == .donating ? script.bluff(at: roundTime) : .none,
            airshipScale: airshipScale(at: videoTime, scene: scene),
            noiseFrame: scene == .donating && stage == .warning ? index : nil,
            stampProgress: scene == .result ? min(1, (videoTime - resultStart) / Self.stampPressDuration) : 0,
            endCardOpacity: min(1, max(0, (videoTime - endCardStart) / Self.crossfadeDuration))
        )
    }

    /// 回収飛行船の大きさ。段階が変わったら、前の段階の大きさから 0.6 秒かけて変える（ゆっくり始めて、ゆっくり止める）
    private func airshipScale(at now: Double, scene: ReplayFrame.Scene) -> Double {
        let emphasized = script.isPractice
        guard scene != .waiting else {
            return Airship.scale(for: .none, emphasized: emphasized)
        }
        let changes = script.stageChanges.filter { videoTime(ofRoundTime: $0.time) <= now + 1e-9 }
        guard let last = changes.last else {
            return Airship.scale(for: .none, emphasized: emphasized)
        }
        let previous = changes.dropLast().last?.stage ?? .none
        let from = Airship.scale(for: previous, emphasized: emphasized)
        let to = Airship.scale(for: last.stage, emphasized: emphasized)
        let progress = min(1, max(0, (now - videoTime(ofRoundTime: last.time)) / Self.airshipTransition))
        let eased = progress * progress * (3 - 2 * progress)
        return from + (to - from) * eased
    }

    /// 効果音（docs/SPEC.md「音と振動」。鳴らし方は `RoundSounds` と同じ）。BGM はまだ無いので入れない
    ///
    /// - 接近（2 段階目）でプロペラを鳴らし始めて大きくしていき、警告（3 段階目）でもう少し大きくする。離したら止める
    /// - 結果で、納品・監査は判子とベル、回収は汽笛
    /// - 明細書が出たら、印字の音
    var soundCues: [ReplaySoundCue] {
        var cues: [ReplaySoundCue] = []
        if let approach = script.stageChanges.first(where: { $0.stage >= .approach }) {
            let startsAtWarning = approach.stage == .warning
            var propeller = ReplaySoundCue(
                effect: .propeller,
                start: videoTime(ofRoundTime: approach.time),
                level: startsAtWarning ? RoundSounds.warningLevel : RoundSounds.approachLevel,
                fadeIn: startsAtWarning ? RoundSounds.warningFade : RoundSounds.approachFadeIn,
                stop: resultStart,
                fadeOut: RoundSounds.propellerFadeOut
            )
            if !startsAtWarning, let warning = script.stageChanges.first(where: { $0.stage == .warning }) {
                propeller.levelChange = .init(
                    time: videoTime(ofRoundTime: warning.time),
                    level: RoundSounds.warningLevel,
                    duration: RoundSounds.warningFade
                )
            }
            cues.append(propeller)
        }
        switch script.result {
        case .delivered, .audited:
            cues.append(ReplaySoundCue(effect: .delivered, start: resultStart))
        case .collected:
            cues.append(ReplaySoundCue(effect: .whistle, start: resultStart))
        }
        cues.append(ReplaySoundCue(effect: .receipt, start: endCardStart + Self.receiptDelay))
        return cues
    }
}

import CoreGraphics
import Foundation

/// 回収演出の時間割。docs/SPEC.md「ゲームルール」の回収（失敗）の演出と「アクセシビリティ」。
///
/// 回収飛行船の影が差し込み、絵が横にずれて崩れ（グリッチ）、画面が揺れてから「全メモリ 回収完了」と判子が出て、
/// 最後に明細と「結果を見る」が出る。経過時間から部品ごとの状態を決める計算だけにして、点滅の回数をテストで確かめる。
nonisolated struct CollectEffectTimeline: Sendable {
    /// 見せ方
    struct Style: Sendable, Equatable {
        /// 控えめにする。グリッチと揺れを止め、飛行船の影と判子だけにする（動きは、ふわっと出すだけ）
        var isSubdued: Bool
        /// 赤と青のずれを動かさずに止める（「点滅する光を弱める」）。グリッチも段階を踏まず、ずれた形で止めて出す
        var freezesColorShift: Bool

        static let full = Self(isSubdued: false, freezesColorShift: false)

        /// 今の設定での見せ方。「控えめにする」かどうかは、ここの `isSubdued` の 1 か所だけで決める。
        /// OS の「視差効果を減らす」か、アプリの設定「回収演出を控えめにする」のどちらかがオンなら控えめにする
        static func current(reduceMotion: Bool, reducesCollectEffect: Bool = false, dimsFlashingLights: Bool) -> Self {
            let isSubdued = reduceMotion || reducesCollectEffect
            return Self(isSubdued: isSubdued, freezesColorShift: dimsFlashingLights)
        }
    }

    /// グリッチ（飛行船の絵が横にずれた帯）の形。最後の `settled` がデザイン（docs/design/Collect.png）の形
    enum Glitch: Int, Sendable, CaseIterable {
        case first
        case second
        case settled
    }

    /// ある時刻の、部品ごとの状態
    struct Frame: Sendable, Equatable {
        var airshipOpacity: Double
        /// 飛行船の定位置からのずれ（飛行船の幅・高さに対する割合）。右上から差し込んで、定位置で止まる
        var airshipOffset: CGSize
        /// nil のときは、ずれた帯を出さない
        var glitch: Glitch?
        /// 画面の横の揺れ（pt）
        var shake: CGFloat
        var headlineOpacity: Double
        /// 大見出しの赤と青のずれ。デザインのずれ（±3pt）に対する倍率
        var colorShift: CGFloat
        var stampOpacity: Double
        /// 判子の大きさ。大きく浮いたところから、紙に押しつけるように 1 に縮む
        var stampScale: CGFloat
        var detailsOpacity: Double
        /// 「端末のメモリはすでに解放済みです」と「結果を見る」
        var actionsOpacity: Double

        /// 「結果を見る」を押せるか（出かかってから押せるようにする）
        var isActionEnabled: Bool {
            actionsOpacity >= 0.5
        }
    }

    /// 1 秒に点滅させてよい回数の上限（光過敏への配慮。docs/SPEC.md「アクセシビリティ」）
    static let maximumFlashesPerSecond = 3

    let style: Style

    /// 最後の部品が出きるまでの秒数
    var duration: TimeInterval {
        style.isSubdued ? 1.3 : 2.05
    }

    /// グリッチの形が切り替わる時刻。切り替わりは 0.35 秒ずつ空けて、どの 1 秒にも 3 回までにする
    var glitchChanges: [TimeInterval] {
        if style.isSubdued {
            return []
        }
        return style.freezesColorShift ? [0.2] : [0.2, 0.55, 0.9]
    }

    func frame(at time: TimeInterval) -> Frame {
        style.isSubdued ? subduedFrame(at: time) : fullFrame(at: time)
    }

    /// 最後の状態（撮影や、演出が終わったあと）
    var finalFrame: Frame {
        frame(at: duration + 1)
    }

    private func fullFrame(at time: TimeInterval) -> Frame {
        let arrival = 1 - Self.easeOut(Self.progress(time, from: 0, over: 0.5))
        let headline = Self.progress(time, from: 0.9, over: 0.45)
        return Frame(
            airshipOpacity: Self.progress(time, from: 0, over: 0.2),
            airshipOffset: CGSize(width: 0.3 * arrival, height: -0.12 * arrival),
            glitch: glitch(at: time),
            shake: Self.shake(at: time, from: 0.2, over: 0.45),
            headlineOpacity: Self.progress(time, from: 0.9, over: 0.15),
            colorShift: style.freezesColorShift ? 1 : 1 + 3 * (1 - Self.easeOut(headline)),
            stampOpacity: Self.progress(time, from: 1.3, over: 0.1),
            stampScale: 1 + 0.8 * (1 - Self.easeIn(Self.progress(time, from: 1.3, over: 0.25))),
            detailsOpacity: Self.progress(time, from: 1.55, over: 0.3),
            actionsOpacity: Self.progress(time, from: 1.75, over: 0.3)
        )
    }

    private func subduedFrame(at time: TimeInterval) -> Frame {
        Frame(
            airshipOpacity: Self.progress(time, from: 0, over: 0.4),
            airshipOffset: .zero,
            glitch: nil,
            shake: 0,
            headlineOpacity: Self.progress(time, from: 0.3, over: 0.3),
            colorShift: 1,
            stampOpacity: Self.progress(time, from: 0.6, over: 0.3),
            stampScale: 1,
            detailsOpacity: Self.progress(time, from: 0.8, over: 0.3),
            actionsOpacity: Self.progress(time, from: 1.0, over: 0.3)
        )
    }

    private func glitch(at time: TimeInterval) -> Glitch? {
        let changes = glitchChanges
        guard let first = changes.first, time >= first else {
            return nil
        }
        if changes.count == 1 {
            return .settled
        }
        let index = changes.lastIndex { time >= $0 } ?? 0
        return Glitch.allCases[min(index, Glitch.allCases.count - 1)]
    }

    /// 0 から 1 に進む割合。終わりの時刻からは、割り算の誤差を残さずに 1 にする
    private static func progress(_ time: TimeInterval, from start: TimeInterval, over length: TimeInterval) -> Double {
        guard time < start + length else {
            return 1
        }
        return max((time - start) / length, 0)
    }

    private static func easeOut(_ value: Double) -> Double {
        1 - (1 - value) * (1 - value)
    }

    private static func easeIn(_ value: Double) -> Double {
        value * value
    }

    /// 細かく揺れて、だんだん収まる（1 秒に 6 往復、最初は ±5pt）
    private static func shake(at time: TimeInterval, from start: TimeInterval, over length: TimeInterval) -> CGFloat {
        let elapsed = time - start
        guard elapsed >= 0, elapsed < length else {
            return 0
        }
        return 5 * (1 - elapsed / length) * sin(2 * .pi * 6 * elapsed)
    }
}

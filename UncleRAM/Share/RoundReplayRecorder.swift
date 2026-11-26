import Observation
import SwiftUI

/// ラウンドの記録の係（リプレイ動画の元。docs/SPEC.md「共有機能」の動画）。
///
/// RoundScreen が `onChange` で、engine の段階・ヒントの段階・はったりを渡す。献上中は 0.1 秒ごとに engine の献上量を読んで残す。
/// engine の確保・解放の処理には手を入れず、値を読むだけにする。計測（`RoundEngine.isAutomated`）と撮影モードでは記録しない
/// （撮影モードは、結果の量から作る決まったリプレイ `RoundReplay.demo` を使う）
@MainActor
@Observable
final class RoundReplayRecorder {
    /// 直前のラウンドのリプレイ。結果が出るまでと、無効になったラウンドは nil
    private(set) var replay: RoundReplay?

    /// 献上中の記録。0.1 秒ごとに書き足すので、観測の対象にしない（ラウンド画面を描き直させない）
    @ObservationIgnored private var recording: RoundRecording?
    @ObservationIgnored private var startedAt: ContinuousClock.Instant?
    /// 離した時刻（押し始めてからの秒数）
    @ObservationIgnored private var releasedAt: Double?
    @ObservationIgnored private var isRecording = false
    @ObservationIgnored private var samplingTask: Task<Void, Never>?

    func phaseChanged(to phase: RoundEngine.Phase, engine: RoundEngine) {
        switch phase {
        case .donating:
            replay = nil
            stopSampling()
            recording = nil
            guard !engine.isAutomated, !ScreenshotDemo.isEnabled else {
                return
            }
            start(engine)
        case .settling:
            releasedAt = elapsed
            stopSampling()
        case let .result(outcome):
            stopSampling()
            if let recording {
                let duration = releasedAt ?? elapsed
                replay = RoundReplay(recording: recording, duration: duration, outcome: outcome)
            } else if ScreenshotDemo.isEnabled {
                replay = RoundReplay.demo(outcome: outcome, safetyLineFill: engine.safetyLineFill)
            } else {
                replay = nil
            }
        case .ready, .unavailable:
            stopSampling()
            recording = nil
            replay = nil
        }
    }

    func hintStageChanged(to stage: RoundPlan.HintStage) {
        guard isRecording else {
            return
        }
        recording?.record(stage: stage, at: elapsed)
    }

    func bluffChanged(to bluff: RoundEngine.Bluff) {
        guard isRecording else {
            return
        }
        let value: RoundRecording.Bluff = switch bluff {
        case .none: .none
        case .showing: .showing
        case .grinning: .grinning
        }
        recording?.record(bluff: value, at: elapsed)
    }

    private var elapsed: Double {
        startedAt.map { $0.duration(to: .now).seconds } ?? 0
    }

    private func start(_ engine: RoundEngine) {
        startedAt = .now
        releasedAt = nil
        var recording = RoundRecording(
            budgetBytes: engine.budgetBytes,
            safetyLineFill: engine.safetyLineFill,
            isPractice: engine.plan?.isPractice ?? false
        )
        recording.record(fill: engine.donatedFill, at: 0)
        recording.record(stage: engine.hintStage, at: 0)
        self.recording = recording
        isRecording = true
        samplingTask = Task { [weak self, weak engine] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(RoundRecording.sampleInterval))
                guard let self, let engine, self.isRecording, engine.phase == .donating else {
                    return
                }
                self.recording?.record(fill: engine.donatedFill, at: self.elapsed)
            }
        }
    }

    private func stopSampling() {
        isRecording = false
        samplingTask?.cancel()
        samplingTask = nil
    }
}

extension EnvironmentValues {
    /// 今の結果のリプレイ。RoundScreen が入れ、共有のプレビュー（動画）が読む
    @Entry var roundReplay: RoundReplay?
}

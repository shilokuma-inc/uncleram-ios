import Foundation
import Observation

/// 速達便 1 ラウンドの状態遷移。docs/SPEC.md「実装の詳細」の「ラウンドの状態と中断」。
///
/// 待機 → 献上中 → （納品 / 回収 / 監査 / 無効）→ 結果。どの終わり方でも、**先に全メモリを解放してから**結果を出す。
/// 時刻と乱数と `MemoryProbe` は外から渡せるので、単体テストでも動かせる。
@MainActor
@Observable
final class RoundEngine {
    enum Phase: Equatable {
        /// 待機（ボタンを押せる）
        case ready
        /// 献上中（長押ししている）
        case donating
        /// 確保を止めて、メモリを解放している
        case settling
        /// 結果
        case result(RoundOutcome)
        /// 遊べない（枠が小さい・発熱している）
        case unavailable(Unavailability)
    }

    enum Unavailability: Equatable {
        /// 枠が 600MB 未満
        case budgetTooSmall(UInt64)
        /// 発熱が serious 以上
        case thermal
    }

    /// 長押しが終わった理由。どれも通常の納品と同じく回収ラインと比べる
    enum ReleaseReason: Equatable {
        /// 指（クリック・スペースキー）を離した
        case released
        /// コントロールセンターや通知で scenePhase が inactive になった
        case inactive
        /// タッチがキャンセルされた
        case touchCancelled
        /// Mac でウィンドウが前面でなくなった（スペースキーを離した通知が届かないため）
        case windowResigned
    }

    /// はったり（偽の気配）の見せ方
    enum Bluff: Equatable {
        case none
        /// 偽の気配を出している（1 秒）
        case showing
        /// にやりと笑って戻るところ
        case grinning
    }

    static let bluffDuration: TimeInterval = 1.0
    static let grinDuration: TimeInterval = 0.8

    private(set) var phase: Phase = .ready
    /// 枠（待機中は今の値、献上中はラウンド開始時の値）
    private(set) var budgetBytes: UInt64 = 0
    private(set) var hintStage: RoundPlan.HintStage = .none
    private(set) var bluff: Bluff = .none
    /// 直前のラウンドで、全解放にかかった秒数
    private(set) var lastReleaseDuration: TimeInterval?
    /// このラウンドの条件（献上中と結果のときだけ）
    private(set) var plan: RoundPlan?
    /// 起動してから届いたメモリ警告・逼迫の数（計測用）
    @ObservationIgnored private(set) var memoryWarningCount = 0

    let client: Client
    let allocator: Allocator
    @ObservationIgnored private let probe: any MemoryProbe
    @ObservationIgnored private var random: SplitMix64
    @ObservationIgnored private let thermalState: () -> ProcessInfo.ThermalState
    @ObservationIgnored private var worker: DonationWorker?
    @ObservationIgnored private var stoppedAtSafetyLine = false
    @ObservationIgnored private var bluffTask: Task<Void, Never>?

    init(
        client: Client = .allocateCorp,
        allocator: Allocator = Allocator(),
        probe: any MemoryProbe = MemoryProbes.current,
        random: SplitMix64 = .randomlySeeded(),
        thermalState: @escaping () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState }
    ) {
        self.client = client
        self.allocator = allocator
        self.probe = probe
        self.random = random
        self.thermalState = thermalState
        refreshBudget()
    }

    /// 確保して書き込み済みの量。毎フレーム読まれるので、観測の対象にしない
    var donatedBytes: UInt64 {
        allocator.allocatedBytes
    }

    /// 献上量（枠に対する割合）
    var donatedFill: Double {
        budgetBytes > 0 ? Double(donatedBytes) / Double(budgetBytes) : 0
    }

    /// 待機中の枠の表示を、今の値に更新する
    func refreshBudget() {
        guard phase == .ready || isUnavailable else {
            return
        }
        budgetBytes = probe.budgetBytes()
        if thermalState().rawValue >= ProcessInfo.ThermalState.serious.rawValue {
            phase = .unavailable(.thermal)
        } else if !SafetyLine(budgetBytes: budgetBytes).isPlayable {
            phase = .unavailable(.budgetTooSmall(budgetBytes))
        } else {
            phase = .ready
        }
    }

    /// ボタンを押した。枠をこの時点で量り直してから献上を始める
    func beginHold() {
        guard phase == .ready else {
            return
        }
        refreshBudget()
        guard phase == .ready else {
            return
        }
        let safety = SafetyLine(budgetBytes: budgetBytes)
        let effectiveLine = safety.effectiveLine(available: probe.availableBytes(allocatedByRound: 0))
        let plan = RoundPlan.make(client: client, safetyLine: effectiveLine, random: &random)
        self.plan = plan
        hintStage = .none
        bluff = .none
        stoppedAtSafetyLine = false
        phase = .donating

        let worker = DonationWorker(
            plan: plan,
            budgetBytes: budgetBytes,
            safety: safety,
            allocator: allocator,
            probe: probe
        ) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        self.worker = worker
        worker.start()
    }

    /// 長押しが終わった（離した・inactive・タッチのキャンセル・ウィンドウが前面でなくなった）
    func endHold(_ reason: ReleaseReason = .released) {
        guard phase == .donating else {
            return
        }
        finish(.delivered)
    }

    /// OS からメモリ警告が届いた。監査が入ったとしてラウンドを止める（納品扱い）
    func memoryWarning() {
        memoryWarningCount += 1
        guard phase == .donating else {
            return
        }
        finish(.audited)
    }

    /// Mac でメモリの逼迫が warning になった。安全ラインに当たったのと同じく、その量で納品する
    func memoryPressureWarning() {
        memoryWarningCount += 1
        guard phase == .donating else {
            return
        }
        stoppedAtSafetyLine = true
        finish(.delivered)
    }

    /// バックグラウンドへの移行や発熱で、ラウンドを無効にする（スコア 0。回収演出なし）
    func void(_ reason: RoundOutcome.VoidReason) {
        switch phase {
        case .donating:
            finish(.voided(reason))
        case .ready where reason == .thermal:
            refreshBudget()
        default:
            break
        }
    }

    /// 結果を閉じて待機に戻る
    func reset() {
        guard case .result = phase else {
            return
        }
        plan = nil
        hintStage = .none
        bluff = .none
        phase = .ready
        refreshBudget()
    }

    /// 結果が出るまで待つ（計測とテスト用）
    func waitForResult() async -> RoundOutcome? {
        while true {
            switch phase {
            case let .result(outcome):
                return outcome
            case .ready, .unavailable:
                return nil
            case .donating, .settling:
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    private var isUnavailable: Bool {
        if case .unavailable = phase {
            return true
        }
        return false
    }

    private func handle(_ event: DonationWorker.Event) {
        guard phase == .donating else {
            return
        }
        switch event {
        case .collected:
            finish(.collected)
        case .stoppedAtSafetyLine:
            stoppedAtSafetyLine = true
            finish(.delivered)
        case let .hintStageChanged(stage):
            hintStage = stage
            if stage != .none {
                cancelBluff()
            }
        case .bluff:
            startBluff()
        }
    }

    private func startBluff() {
        bluffTask?.cancel()
        bluff = .showing
        bluffTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.bluffDuration))
            guard !Task.isCancelled, let self, self.bluff == .showing else {
                return
            }
            self.bluff = .grinning
            try? await Task.sleep(for: .seconds(Self.grinDuration))
            guard !Task.isCancelled, self.bluff == .grinning else {
                return
            }
            self.bluff = .none
        }
    }

    private func cancelBluff() {
        bluffTask?.cancel()
        bluffTask = nil
        bluff = .none
    }

    /// 確保を止め、量を確定し、全メモリを解放してから結果を出す
    private func finish(_ kind: RoundOutcome.Kind) {
        guard phase == .donating, let worker, let plan else {
            return
        }
        phase = .settling
        cancelBluff()
        self.worker = nil
        let budget = budgetBytes
        let allocator = allocator
        Task {
            await worker.stop()
            let donated = allocator.allocatedBytes
            // 離したのと同時に回収ラインを越えていたら、回収にする（比べるのは離した瞬間の量）
            let crossedLine = Double(donated) > plan.collectionLine * Double(budget)
            let kind: RoundOutcome.Kind = switch kind {
            case .voided:
                kind
            default:
                crossedLine ? .collected : kind
            }
            let duration = await Task.detached(priority: .userInitiated) {
                allocator.releaseAll()
            }.value
            lastReleaseDuration = duration
            phase = .result(
                RoundOutcome(
                    kind: kind,
                    plan: plan,
                    budgetBytes: budget,
                    donatedBytes: donated,
                    stoppedAtSafetyLine: stoppedAtSafetyLine
                )
            )
        }
    }
}

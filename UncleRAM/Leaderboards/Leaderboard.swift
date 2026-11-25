import Foundation

/// ランキングに入るモード。定期便は強化や保険が効くので、ここに足さない（docs/SPEC.md「プレイモード」「ランキング」）。
///
/// raw value はランキングの ID の真ん中（`lb.<raw value>.`）。
nonisolated enum RankingMode: String, Sendable, Codable, CaseIterable {
    /// 速達便
    case express
    /// デイリー。Game Center の繰り返し型ランキング（期間 1 日、世界標準時 0 時に切り替わる）
    case daily
}

/// 14 本のランキングの 1 本。ID は `UncleRAM/GameCenterResources.gamekit` と同じ
nonisolated struct Leaderboard: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        /// 腕前スコア（全端末で 1 本）
        case skill
        /// 献上量（搭載メモリのクラスごと）
        case donated(MemoryClass)
    }

    static let identifierPrefix = "jp.shilokuma.UncleRAM.lb"

    /// 速達便とデイリーのそれぞれに、腕前 1 本と献上量 6 本
    static let all: [Leaderboard] = RankingMode.allCases.flatMap { mode in
        [Leaderboard(mode: mode, kind: .skill)] + MemoryClass.allCases.map { Leaderboard(mode: mode, kind: .donated($0)) }
    }

    let mode: RankingMode
    let kind: Kind

    /// 例: `jp.shilokuma.UncleRAM.lb.express.skill`、`jp.shilokuma.UncleRAM.lb.daily.mb_mac_m`
    var identifier: String {
        switch kind {
        case .skill:
            "\(Self.identifierPrefix).\(mode.rawValue).skill"
        case .donated(let memoryClass):
            "\(Self.identifierPrefix).\(mode.rawValue).mb_\(memoryClass.rawValue)"
        }
    }
}

/// スコアに付ける context の値。端末の種類と搭載メモリのクラスだけを入れる（機種名・正確な搭載メモリ・端末 ID は入れない）。
///
/// 10 進の桁で分ける: 版 × 100 + 端末の種類 × 10 + クラスの大きさ。App Store Connect で異常なスコアを調べるときに、そのまま読める。
/// - 端末の種類: iPhone 1・iPad 2・Mac 3（`DeviceKind`）
/// - クラスの大きさ: 小 1・中 2・大 3（`MemoryClass.tier`。Mac かどうかは端末の種類で分かる）
/// - 例: 123 = 版 1・iPad・16GB 以上。0 は context を付けていないスコア
nonisolated enum LeaderboardContext {
    /// 符号化の版。中身を変えるときは上げ、古い版も読めるようにする
    static let version = 1

    static func encode(kind: DeviceKind, memoryClass: MemoryClass) -> Int {
        version * 100 + kind.rawValue * 10 + memoryClass.tier
    }

    static func encode(_ device: DeviceMemoryProfile) -> Int {
        encode(kind: device.kind, memoryClass: device.memoryClass)
    }

    /// ランキングの画面で「○○（iPad・16GB 以上）」と添えるために読み戻す。読めない値は nil
    static func decode(_ context: Int) -> (kind: DeviceKind, memoryClass: MemoryClass)? {
        guard context / 100 == version,
              let kind = DeviceKind(rawValue: context / 10 % 10),
              let memoryClass = MemoryClass(kind: kind, tier: context % 10) else {
            return nil
        }
        return (kind, memoryClass)
    }
}

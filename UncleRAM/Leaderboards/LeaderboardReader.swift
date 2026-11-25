import Foundation
import GameKit

/// ランキングの 1 行（Game Center のニックネーム・順位・スコア・端末の種類とクラス）
nonisolated struct LeaderboardRow: Sendable, Equatable, Identifiable {
    let rank: Int
    /// Game Center のニックネーム。名前の登録・変更・不適切な名前への対応は Apple が行う（アプリには名前の入力欄を置かない）
    let displayName: String
    let score: Int
    /// スコアに付けた context（`LeaderboardContext`）。読めないときは nil
    let context: Int
    let isLocalPlayer: Bool

    var id: Int { rank }

    /// 「（iPad・16GB 以上）」のように添える端末の種類とクラス
    var deviceLabel: String? {
        LeaderboardContext.decode(context).map { "\($0.kind.label)・\($0.memoryClass.shortLabel)" }
    }
}

/// 1 本のランキングを読んだ結果
nonisolated struct LeaderboardPage: Sendable, Equatable {
    var rows: [LeaderboardRow]
    /// 自分の行。上位に入っていなくても出す。記録が無ければ nil
    var localPlayer: LeaderboardRow?
    /// 参加している人数
    var totalPlayers: Int
}

/// 「全体」と「友だち」
nonisolated enum LeaderboardScope: String, Sendable, CaseIterable {
    case global
    case friends
}

/// ランキングを読む。テストでは偽物に差し替える
protocol LeaderboardReading: AnyObject {
    func load(_ leaderboard: Leaderboard, scope: LeaderboardScope, top: Int) async throws -> LeaderboardPage
}

/// GameKit から読む。繰り返し型（デイリー）は、今の回の順位になる
final class GameKitLeaderboardReader: LeaderboardReading {
    func load(_ leaderboard: Leaderboard, scope: LeaderboardScope, top: Int) async throws -> LeaderboardPage {
        guard let board = try await GKLeaderboard.loadLeaderboards(IDs: [leaderboard.identifier]).first else {
            return LeaderboardPage(rows: [], localPlayer: nil, totalPlayers: 0)
        }
        let (local, entries, total) = try await board.loadEntries(
            for: scope == .global ? .global : .friendsOnly,
            timeScope: .allTime,
            range: NSRange(location: 1, length: max(1, top))
        )
        let localID = GKLocalPlayer.local.gamePlayerID
        func row(_ entry: GKLeaderboard.Entry) -> LeaderboardRow {
            LeaderboardRow(
                rank: entry.rank,
                displayName: entry.player.displayName,
                score: entry.score,
                context: entry.context,
                isLocalPlayer: entry.player.gamePlayerID == localID
            )
        }
        return LeaderboardPage(rows: entries.map(row), localPlayer: local.map(row), totalPlayers: total)
    }
}

nonisolated extension DeviceKind {
    /// 「iPhone」「iPad」「Mac」
    var label: String {
        switch self {
        case .iPhone: "iPhone"
        case .iPad: "iPad"
        case .mac: "Mac"
        }
    }
}

nonisolated extension MemoryClass {
    /// ランキングの名前と同じクラスの書き方（「iPhone・iPad 8GB 以下」「Mac 24〜36GB」など）
    var title: String {
        switch self {
        case .iosSmall: String(localized: "iPhone・iPad 8GB 以下")
        case .iosMedium: String(localized: "iPhone・iPad 12GB")
        case .iosLarge: String(localized: "iPhone・iPad 16GB 以上")
        case .macSmall: String(localized: "Mac 18GB 以下")
        case .macMedium: String(localized: "Mac 24〜36GB")
        case .macLarge: String(localized: "Mac 48GB 以上")
        }
    }

    /// 行に添える短い書き方（「8GB 以下」「24〜36GB」など）
    var shortLabel: String {
        switch self {
        case .iosSmall: String(localized: "8GB 以下")
        case .iosMedium: "12GB"
        case .iosLarge: String(localized: "16GB 以上")
        case .macSmall: String(localized: "18GB 以下")
        case .macMedium: "24〜36GB"
        case .macLarge: String(localized: "48GB 以上")
        }
    }
}

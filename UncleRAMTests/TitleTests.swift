import Foundation
import Testing
@testable import UncleRAM

/// タイトルの会長の一言と、端末の中に残す値（初回の案内・設定・初期化）
struct TitleTests {
    /// ランキングのメモリのクラスでいちばん小さいとき（iPhone・iPad は 8GB 以下、Mac は 18GB 以下）だけ「……まあ、いいでしょう」
    @Test(arguments: [
        (DeviceKind.iPhone, 4, ChairmanGreeting.modest),
        (.iPhone, 8, .modest),
        (.iPhone, 12, .honored),
        (.iPad, 16, .honored),
        (.mac, 16, .modest),
        (.mac, 18, .modest),
        (.mac, 24, .honored),
        (.mac, 64, .honored)
    ])
    func greetingFollowsMemoryClass(kind: DeviceKind, gigabytes: Int, expected: ChairmanGreeting) {
        #expect(ChairmanGreeting.forProfile(DeviceMemoryProfile(kind: kind, nominalGigabytes: gigabytes)) == expected)
    }

    /// 初回の案内を閉じたことは、次に起動したときも覚えている
    @Test
    func safetyNoticeAcknowledgementPersists() throws {
        let suiteName = "UncleRAMTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = LocalStore(defaults: defaults)
        #expect(!first.hasAcknowledgedSafetyNotice)
        first.hasAcknowledgedSafetyNotice = true

        #expect(LocalStore(defaults: defaults).hasAcknowledgedSafetyNotice)
    }

    /// データの初期化は、初回の案内を閉じたことも、設定も、ランキングの自分の最高記録と送り直し待ちも消す（次に起動したときも消えたまま）
    @Test
    func resetAllClearsRecordsAndSettings() throws {
        let suiteName = "UncleRAMTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LocalStore(defaults: defaults)
        store.hasAcknowledgedSafetyNotice = true
        store.tapToDonate = true
        store.reducesCollectEffect = true
        #expect(LocalStore(defaults: defaults).tapToDonate)
        #expect(LocalStore(defaults: defaults).reducesCollectEffect)

        defaults.set(Data("{}".utf8), forKey: UserDefaultsRankingStore.personalBestsKey)
        defaults.set(Data("{}".utf8), forKey: UserDefaultsRankingStore.pendingScoresKey)

        store.resetAll()
        #expect(defaults.object(forKey: UserDefaultsRankingStore.personalBestsKey) == nil)
        #expect(defaults.object(forKey: UserDefaultsRankingStore.pendingScoresKey) == nil)
        #expect(!store.hasAcknowledgedSafetyNotice)
        #expect(!store.tapToDonate)
        let reloaded = LocalStore(defaults: defaults)
        #expect(!reloaded.hasAcknowledgedSafetyNotice)
        #expect(!reloaded.tapToDonate)
        #expect(!reloaded.reducesCollectEffect)
    }
}

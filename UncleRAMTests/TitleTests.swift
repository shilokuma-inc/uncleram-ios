import Foundation
import Testing
@testable import UncleRAM

/// タイトルの会長の一言と、端末の中に残す値
struct TitleTests {
    /// メモリのクラスでいちばん小さいとき（iPhone・iPad は 8GB 以下、Mac は 16GB 以下）だけ「……まあ、いいでしょう」
    @Test(arguments: [
        (4, false, ChairmanGreeting.modest),
        (8, false, .modest),
        (12, false, .honored),
        (16, false, .honored),
        (8, true, .modest),
        (16, true, .modest),
        (24, true, .honored),
        (64, true, .honored)
    ])
    func greetingFollowsInstalledMemory(gigabytes: Int, isMac: Bool, expected: ChairmanGreeting) {
        #expect(ChairmanGreeting.forInstalledMemory(gigabytes: gigabytes, isMac: isMac) == expected)
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
}

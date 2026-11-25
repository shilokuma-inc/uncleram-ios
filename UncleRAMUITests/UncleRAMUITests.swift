//
//  UncleRAMUITests.swift
//  UncleRAMUITests
//
//  Created by 村石 拓海 on 2024/05/12.
//

import XCTest

final class UncleRAMUITests: XCTestCase {
    override func setUpWithError() throws {
        // UI テストでは失敗した時点で即座に止める
        continueAfterFailure = false
    }

    /// 起動する。初回の案内を閉じたかは、起動引数（UserDefaults の引数のドメイン）で決めて、前のテストの状態に左右されないようにする
    @MainActor
    private func launch(acknowledgedSafetyNotice: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hasAcknowledgedSafetyNotice", acknowledgedSafetyNotice ? "YES" : "NO"]
        app.launch()
        return app
    }

    /// タイトルの「献上をはじめる」から、速達便のラウンド画面に入る
    @MainActor
    private func openRound(_ app: XCUIApplication) {
        let start = app.buttons["献上をはじめる"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.buttons["献上する"].waitForExistence(timeout: 5))
    }

    /// 最初の起動では、初回の案内が出る。「承知しました」で閉じると、タイトルが使えるようになる
    @MainActor
    func testFirstLaunchShowsSafetyNotice() throws {
        let app = launch(acknowledgedSafetyNotice: false)

        let acknowledge = app.buttons["承知しました"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 5))
        acknowledge.tap()
        let dismissed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: acknowledge)
        wait(for: [dismissed], timeout: 5)
        XCTAssertTrue(app.buttons["献上をはじめる"].isHittable)
    }

    /// 起動するとタイトルが出て、「献上をはじめる」で速達便のラウンド画面（長押しのボタン）に入る
    @MainActor
    func testTitleStartsExpressRound() throws {
        let app = launch()

        openRound(app)
    }

    /// 右上の「計測」を押すと、計測のメニューが開く（紙の画像などの飾りがタップを吸い取らないこと）
    @MainActor
    func testBenchMenuOpens() throws {
        let app = launch()
        openRound(app)

        let bench = app.buttons["計測"]
        XCTAssertTrue(bench.waitForExistence(timeout: 5))
        bench.tap()
        XCTAssertTrue(app.buttons["100 ラウンド（全体を乱数で埋める）"].waitForExistence(timeout: 5))
    }

    /// 長押しして離すと、結果（もう一度献上する）が出る。1.5 秒では枠の 15% ほどなので、回収ラインには届かない。
    /// 結果の「タイトルへ」でタイトルに戻る
    @MainActor
    func testHoldAndReleaseShowsResult() throws {
        let app = launch()
        openRound(app)

        app.buttons["献上する"].press(forDuration: 1.5)
        XCTAssertTrue(app.buttons["もう一度献上する"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ラインはここだった"].exists)

        app.buttons["タイトルへ"].tap()
        XCTAssertTrue(app.buttons["献上をはじめる"].waitForExistence(timeout: 5))
    }
}

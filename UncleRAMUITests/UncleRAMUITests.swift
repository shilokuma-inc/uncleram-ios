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

    /// 起動すると、速達便のラウンド画面（長押しのボタン）が出る
    @MainActor
    func testLaunchShowsRoundScreen() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["献上する"].waitForExistence(timeout: 5))
    }

    /// 長押しして離すと、結果（もう一度献上する）が出る。1.5 秒では枠の 15% ほどなので、回収ラインには届かない
    @MainActor
    func testHoldAndReleaseShowsResult() throws {
        let app = XCUIApplication()
        app.launch()

        let button = app.buttons["献上する"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.press(forDuration: 1.5)
        XCTAssertTrue(app.buttons["もう一度献上する"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ラインはここだった"].exists)
    }
}

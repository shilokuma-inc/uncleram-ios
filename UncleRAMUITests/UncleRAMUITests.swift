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
    private func launch(acknowledgedSafetyNotice: Bool = true, tapToDonate: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hasAcknowledgedSafetyNotice", acknowledgedSafetyNotice ? "YES" : "NO"]
        app.launchArguments += ["-tapToDonate", tapToDonate ? "YES" : "NO"]
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

    /// 設定「タップで献上」のときは、1 回目のタップで献上を始め、もう一度タップすると納品する
    @MainActor
    func testTapToDonateStartsAndDelivers() throws {
        let app = launch(tapToDonate: true)
        openRound(app)

        let button = app.buttons["献上する"]
        button.tap()
        sleep(1)
        button.tap()
        XCTAssertTrue(app.buttons["もう一度献上する"].waitForExistence(timeout: 5))
    }

    /// タイトルの「?」で遊び方の 3 コマが開き、「閉じる」（×）で閉じる
    @MainActor
    func testHowToPlayOpensAndCloses() throws {
        let app = launch()

        let help = app.buttons["遊び方"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.tap()
        let close = app.buttons["閉じる"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        let dismissed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: close)
        wait(for: [dismissed], timeout: 5)
        XCTAssertTrue(app.buttons["献上をはじめる"].isHittable)
    }

    /// タイトルの「設定」で設定が開き、「閉じる」でタイトルに戻る
    @MainActor
    func testSettingsOpensAndCloses() throws {
        let app = launch()

        let settings = app.buttons["設定"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 5))
        app.buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["献上をはじめる"].waitForExistence(timeout: 5))
    }

    /// 回収されたら、結果の前に回収演出が出る。演出の終わりに出る「結果を見る」で、結果（ラインを明かす画面）に進む。
    /// 遊んで回収させると時間がかかり、ラインも乱数で決まるので、撮影モードの回収演出の場面で確かめる
    @MainActor
    func testCollectEffectLeadsToResult() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-screenshot-demo", "-screenshot-scene", "collect"]
        app.launch()

        let showResult = app.buttons["結果を見る"]
        XCTAssertTrue(showResult.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["端末のメモリはすでに解放済みです"].exists)
        showResult.tap()
        XCTAssertTrue(app.buttons["もう一度献上する"].waitForExistence(timeout: 5))
        XCTAssertFalse(showResult.exists)
    }
}

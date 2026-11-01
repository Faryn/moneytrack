import XCTest

@MainActor
final class ConnectedFlowTests: XCTestCase {
    func testExplicitCopyLoginSyncAndKeychainRelaunch() throws {
        guard ProcessInfo.processInfo.environment["MONEYTRACK_TEST_SERVER"] == "http://127.0.0.1:4004" else {
            throw XCTSkip("Run scripts/check-connected for the isolated real-server check.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["MONEYTRACK_TEST_TODAY"] = "2026-01-15"
        app.launchEnvironment["MONEYTRACK_TEST_SERVER"] = "http://127.0.0.1:4004"
        app.launch()
        XCTAssertTrue(app.buttons["budget.setup"].waitForExistence(timeout: 10))
        app.buttons["budget.setup"].tap()
        app.buttons["category.add"].tap()
        app.textFields["category.name"].tap(); app.textFields["category.name"].typeText("Restaurants")
        app.textFields["category.annual"].tap(); app.textFields["category.annual"].typeText("1200")
        app.buttons["category.save"].tap()
        app.navigationBars["Yearly Plan"].buttons["Close"].tap()
        app.buttons["expense.add"].tap()
        app.textFields["expense.amount"].tap(); app.textFields["expense.amount"].typeText("78")
        app.textFields["expense.description"].tap(); app.textFields["expense.description"].typeText("Theodor")
        app.buttons["expense.save"].tap()
        app.buttons["account.open"].tap()
        app.buttons["account.sign-in"].tap()
        app.textFields["login.username"].tap(); app.textFields["login.username"].typeText("ui-connected-fixture")
        app.secureTextFields["login.password"].tap(); app.secureTextFields["login.password"].typeText("fixture-passphrase-2026")
        let copyToggle = app.switches["login.copy-local"]
        XCTAssertEqual(copyToggle.value as? String, "0")
        copyToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: copyToggle)
        wait(for: [enabled], timeout: 3)
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.buttons["category-Restaurants"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["budget.remaining"].value as? String, "€22.00")
        app.buttons["account.open"].tap()
        XCTAssertTrue(app.staticTexts["Up to date"].waitForExistence(timeout: 20))
        app.navigationBars["Account"].buttons["Close"].tap()
        app.terminate()
        app.launchArguments.removeAll { $0 == "--reset-ui-testing-data" }
        app.launch()
        XCTAssertTrue(app.buttons["category-Restaurants"].waitForExistence(timeout: 10))
        app.buttons["account.open"].tap()
        let accountIdentity = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ OR value == %@", "ui-connected-fixture", "ui-connected-fixture")).firstMatch
        XCTAssertTrue(accountIdentity.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Up to date"].waitForExistence(timeout: 20))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Connected native account"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

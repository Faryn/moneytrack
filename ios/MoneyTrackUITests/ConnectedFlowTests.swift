import XCTest

@MainActor
final class ConnectedFlowTests: XCTestCase {
    func testExplicitCopyLoginSyncAndKeychainRelaunch() throws {
        guard ProcessInfo.processInfo.environment["MONEYTRACK_TEST_SERVER"] == "http://127.0.0.1:4004" else {
            throw XCTSkip("Run scripts/check-connected for the isolated real-server check.")
        }
        let interruption = addUIInterruptionMonitor(withDescription: "System password save") { alert in
            if alert.buttons["Not Now"].exists { alert.buttons["Not Now"].tap(); return true }
            return false
        }
        defer { removeUIInterruptionMonitor(interruption) }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["MONEYTRACK_TEST_TODAY"] = "2026-01-15"
        app.launchEnvironment["MONEYTRACK_TEST_SERVER"] = "http://127.0.0.1:4004"
        app.launch()
        XCTAssertTrue(app.buttons["budget.setup"].waitForExistence(timeout: 10))
        app.buttons["budget.setup"].tap()
        app.textFields["budget.annual"].tap(); app.textFields["budget.annual"].typeText("1200")
        app.buttons["budget.save"].tap()
        app.buttons["category.add"].tap()
        app.textFields["category.name"].tap(); app.textFields["category.name"].typeText("Restaurants")
        app.textFields["category.annual"].tap(); app.textFields["category.annual"].typeText("1200")
        app.buttons["category.save"].tap()
        app.navigationBars["Yearly Plan"].buttons["Close"].tap()
        app.tabBars.buttons["Expenses"].tap()
        app.buttons["expense.add"].tap()
        app.buttons["expense.quick-details"].tap()
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
        if app.buttons["Not Now"].waitForExistence(timeout: 5) { app.buttons["Not Now"].tap() }
        let connected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND hittable == true", "ui-connected-fixture"), object: app.buttons["account.open"])
        wait(for: [connected], timeout: 30)
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
        app.buttons["account.email"].tap()
        let email = app.textFields["email.address"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap(); email.typeText("ui-sharing-fixture@example.org")
        app.buttons["email.send"].tap()
        XCTAssertTrue(app.textFields["email.code"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["email.verify"].isEnabled)
        if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        let emailScreen = XCTAttachment(screenshot: app.screenshot())
        emailScreen.name = "Native email verification"
        emailScreen.lifetime = .keepAlways
        add(emailScreen)
        app.navigationBars["Email for Sharing"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Account"].buttons["Close"].tap()
        app.tabBars.buttons["Expenses"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'expense-row-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        app.buttons["expense.actions"].tap(); app.buttons["Share Expense"].tap()
        let recipient = app.textFields["sharing.email"]
        XCTAssertTrue(recipient.waitForExistence(timeout: 5))
        recipient.tap(); recipient.typeText("shared-b@example.org")
        app.buttons["sharing.save"].tap()
        app.tabBars.buttons["Budget"].tap()
        XCTAssertEqual(app.staticTexts["budget.remaining"].value as? String, "€61.00")
        app.tabBars.buttons["Shared"].tap()
        let person = app.buttons["sharing.person.shared-b-fixture"]
        XCTAssertTrue(person.waitForExistence(timeout: 20))
        let peopleScreen = XCTAttachment(screenshot: app.screenshot())
        peopleScreen.name = "Shared people with aligned balances"; peopleScreen.lifetime = .keepAlways; add(peopleScreen)
        person.tap()
        XCTAssertTrue(app.staticTexts["Owes you €39.00"].waitForExistence(timeout: 10))
        app.buttons["sharing.settle"].tap()
        let settlement = app.textFields["settle.amount"]
        XCTAssertTrue(settlement.waitForExistence(timeout: 5))
        let previous = settlement.value as? String ?? ""
        settlement.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        settlement.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + "15")
        XCTAssertEqual(settlement.value as? String, "15")
        app.buttons["settle.save"].tap()
        XCTAssertTrue(app.staticTexts["Owes you €24.00"].waitForExistence(timeout: 10))
        let synced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["sharing.pending"])
        wait(for: [synced], timeout: 20)
        let sharedScreen = XCTAttachment(screenshot: app.screenshot())
        sharedScreen.name = "Native shared balance after partial repayment"; sharedScreen.lifetime = .keepAlways; add(sharedScreen)
        app.tabBars.buttons["Budget"].tap()
        XCTAssertEqual(app.staticTexts["budget.remaining"].value as? String, "€61.00")
    }
}

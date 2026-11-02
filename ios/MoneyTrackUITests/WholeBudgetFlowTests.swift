import XCTest

@MainActor
final class WholeBudgetFlowTests: XCTestCase {
    func testTotalFirstGuiltFreeSpendingAndReachableEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["MONEYTRACK_TEST_TODAY"] = "2026-01-15"
        app.launch()
        XCTAssertTrue(app.buttons["budget.setup"].waitForExistence(timeout: 10)); app.buttons["budget.setup"].tap()
        XCTAssertFalse(app.buttons["category.add"].exists)
        app.textFields["budget.annual"].tap(); app.textFields["budget.annual"].typeText("1200")
        app.buttons["budget.save"].tap()
        XCTAssertTrue(app.buttons["category.add"].waitForExistence(timeout: 5)); app.buttons["category.add"].tap()
        app.textFields["category.name"].tap(); app.textFields["category.name"].typeText("Food")
        app.textFields["category.annual"].tap(); app.textFields["category.annual"].typeText("600")
        app.buttons["category.save"].tap()
        app.navigationBars["Yearly Plan"].buttons["Close"].tap()
        XCTAssertFalse(app.buttons["expense.add"].exists)
        app.tabBars.buttons["Shared"].tap()
        XCTAssertFalse(app.buttons["expense.add"].exists)
        app.tabBars.buttons["Expenses"].tap()
        let add = app.buttons["expense.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertLessThan(add.frame.width, 80)
        XCTAssertGreaterThan(add.frame.midX, app.frame.width * 0.75)
        XCTAssertGreaterThan(add.frame.midY, app.frame.height * 0.65)
        XCTAssertLessThan(add.frame.midY, app.tabBars.firstMatch.frame.midY)
        add.tap()
        app.textFields["expense.amount"].tap(); app.textFields["expense.amount"].typeText("20")
        app.textFields["expense.description"].tap()
        XCTAssertEqual(app.textFields["expense.amount"].value as? String, "20.00")
        XCTAssertTrue(app.textFields["expense.amount"].label.contains("euros"))
        app.textFields["expense.description"].typeText("Coffee and friends")
        let entry = XCTAttachment(screenshot: app.screenshot())
        entry.name = "EUR amount and keyboard Save Expense"; entry.lifetime = .keepAlways; self.add(entry)
        XCTAssertTrue(app.buttons["expense.keyboard-save"].isEnabled)
        app.buttons["expense.keyboard-save"].tap()
        XCTAssertTrue(add.isHittable)
        let expenses = XCTAttachment(screenshot: app.screenshot())
        expenses.name = "Expenses with compact floating plus"; expenses.lifetime = .keepAlways; self.add(expenses)
        app.tabBars.buttons["Budget"].tap()
        XCTAssertEqual(app.staticTexts["budget.remaining"].value as? String, "€80.00")
        XCTAssertEqual(app.staticTexts["budget.guilt-free.remaining"].value as? String, "€30.00")
        XCTAssertTrue(app.buttons["category-Food"].label.contains("€50.00"))
        XCTAssertTrue(app.buttons["category-Food"].isHittable, "Category budgets should be visible alongside the main balance without scrolling.")
        XCTAssertFalse(app.buttons["expense.add"].exists)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Whole budget with category amounts"; image.lifetime = .keepAlways; self.add(image)
        app.terminate(); app.launchArguments.removeAll { $0 == "--reset-ui-testing-data" }; app.launch()
        XCTAssertTrue(app.buttons["category-Food"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["budget.guilt-free.remaining"].value as? String, "€30.00")
    }
}

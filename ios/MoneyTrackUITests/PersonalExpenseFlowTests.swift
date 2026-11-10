import XCTest

@MainActor
final class PersonalExpenseFlowTests: XCTestCase {
    func testBudgetAndExpenseSurviveRelaunchAndDeletionRestoresBudget() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["MONEYTRACK_TEST_TODAY"] = "2026-01-15"
        app.launch()
        XCTAssertTrue(app.buttons["budget.setup"].waitForExistence(timeout: 10))
        app.buttons["budget.setup"].tap()
        app.textFields["budget.annual"].tap(); app.textFields["budget.annual"].typeText("1200")
        app.buttons["budget.save"].tap()
        app.buttons["category.add"].tap()
        app.textFields["category.name"].tap()
        app.textFields["category.name"].typeText("Restaurants")
        app.textFields["category.annual"].tap()
        app.textFields["category.annual"].typeText("1200")
        app.buttons["category.save"].tap()
        app.navigationBars["Yearly Plan"].buttons["Close"].tap()
        XCTAssertTrue(app.buttons["category-Restaurants"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Expenses"].tap()
        app.buttons["expense.add"].tap()
        app.buttons["expense.quick-details"].tap()
        let amount = app.textFields["expense.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        amount.tap()
        amount.typeText("78")
        app.textFields["expense.description"].tap()
        app.textFields["expense.description"].typeText("Theodor")
        app.buttons["expense.save"].tap()
        app.tabBars.buttons["Budget"].tap()
        XCTAssertEqual(app.staticTexts["budget.remaining"].value as? String, "€22.00")
        app.terminate()
        app.launchArguments.removeAll { $0 == "--reset-ui-testing-data" }
        app.launch()
        XCTAssertTrue(app.buttons["category-Restaurants"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["budget.remaining"].value as? String, "€22.00")
        app.tabBars.buttons["Expenses"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'expense-row-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Theodor"))
        row.tap()
        app.buttons["expense.actions"].tap()
        app.buttons["Edit Expense"].tap()
        let editedAmount = app.textFields["expense.amount"]
        XCTAssertTrue(editedAmount.waitForExistence(timeout: 5))
        let originalText = editedAmount.value as? String ?? ""
        editedAmount.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        editedAmount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: originalText.count) + "98")
        XCTAssertEqual(editedAmount.value as? String, "98")
        app.buttons["expense.save"].tap()
        app.tabBars.buttons["Budget"].tap()
        XCTAssertEqual(app.staticTexts["budget.remaining"].value as? String, "€2.00")
        app.tabBars.buttons["Expenses"].tap()
        app.buttons["expense.actions"].tap()
        app.buttons["Delete Expense"].tap()
        app.buttons["Delete Expense"].tap()
        app.tabBars.buttons["Budget"].tap()
        XCTAssertEqual(app.staticTexts["budget.remaining"].value as? String, "€100.00")
        app.buttons["budget.yearly-plan"].tap()
        let total = app.textFields["budget.annual"]
        let oldTotal = total.value as? String ?? ""
        total.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        total.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldTotal.count) + "3600")
        XCTAssertEqual(total.value as? String, "3,600")
        app.buttons["budget.save"].tap(); app.buttons["Update Yearly Budget"].tap()
        app.buttons["category.add"].tap()
        app.textFields["category.name"].tap()
        app.textFields["category.name"].typeText("Groceries")
        app.textFields["category.annual"].tap()
        app.textFields["category.annual"].typeText("2400")
        app.buttons["category.save"].tap()
        app.navigationBars["Yearly Plan"].buttons["Close"].tap()
        app.tabBars.buttons["Expenses"].tap()
        app.buttons["expense.add"].tap()
        app.buttons["expense.quick-details"].tap()
        app.textFields["expense.amount"].tap()
        app.textFields["expense.amount"].typeText("150")
        app.buttons["expense.category"].tap()
        XCTAssertTrue(app.buttons["Restaurants"].waitForExistence(timeout: 5))
        app.buttons["Restaurants"].tap()
        app.buttons["expense.save"].tap()
        app.tabBars.buttons["Budget"].tap()
        XCTAssertEqual(app.staticTexts["budget.remaining"].value as? String, "€150.00")
        XCTAssertTrue(app.buttons["category-Restaurants"].label.contains("over budget"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Budget with available and overspent categories"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    func testIncomeIsPositiveAndDoesNotConsumeBudget() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["MONEYTRACK_TEST_TODAY"] = "2026-01-15"
        app.launch()
        XCTAssertTrue(app.buttons["budget.setup"].waitForExistence(timeout: 10))
        app.buttons["budget.setup"].tap()
        app.textFields["budget.annual"].tap(); app.textFields["budget.annual"].typeText("1200")
        app.buttons["budget.save"].tap()
        app.navigationBars["Yearly Plan"].buttons["Close"].tap()
        app.tabBars.buttons["Expenses"].tap()
        app.buttons["expense.add"].tap(); app.buttons["expense.quick-details"].tap()
        app.buttons["expense.kind"].tap()
        app.buttons["Income"].tap()
        app.textFields["expense.amount"].tap(); app.textFields["expense.amount"].typeText("2000")
        app.textFields["expense.description"].tap(); app.textFields["expense.description"].typeText("Salary")
        app.buttons["expense.save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'expense-row-'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Income"))
        XCTAssertTrue(row.label.contains("+€2,000.00"))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Income and separate monthly spending"; shot.lifetime = .keepAlways; add(shot)
        app.tabBars.buttons["Budget"].tap()
        XCTAssertEqual(app.staticTexts["budget.remaining"].value as? String, "€0.00")
        app.tabBars.buttons["Expenses"].tap(); row.tap()
        app.buttons["expense.actions"].tap()
        XCTAssertFalse(app.buttons["Share Expense"].exists)
        app.buttons["Delete Income"].tap(); app.buttons["Delete Income"].tap()
        XCTAssertFalse(row.exists)
    }

}

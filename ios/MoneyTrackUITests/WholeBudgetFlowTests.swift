import XCTest
import UIKit

@MainActor
final class WholeBudgetFlowTests: XCTestCase {
    func testGermanQuickEntryAndPrivacy() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data", "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["MONEYTRACK_TEST_TODAY"] = "2026-01-15"
        app.launch()
        XCTAssertTrue(app.buttons["Budget einrichten"].waitForExistence(timeout: 10))
        app.buttons["account.open"].tap()
        app.buttons["account.privacy"].tap()
        XCTAssertTrue(app.navigationBars["Datenschutz"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["privacy.summary"].label.contains("Spendie verwendet deine Daten"))
        app.navigationBars["Datenschutz"].buttons.firstMatch.tap()
        app.navigationBars["Konto"].buttons["Schließen"].tap()

        tapTab("Ausgaben", in: app)
        app.buttons["expense.add"].tap()
        let field = app.textFields["expense.quick-entry"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("12,50 Kaffee")
        XCTAssertEqual(app.buttons["expense.quick-save"].label, "Speichern")
        XCTAssertTrue(app.staticTexts["expense.quick-preview"].label.contains("12,50"))
        XCTAssertEqual(app.buttons["expense.quick-category"].value as? String, "Keine Kategorie")
        app.buttons["expense.quick-save"].tap()
        let booking = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "expense-row-")).firstMatch
        XCTAssertTrue(booking.waitForExistence(timeout: 5))
        XCTAssertTrue(booking.label.contains("Kaffee"))
        XCTAssertTrue(booking.label.contains("Ohne Kategorie"))
    }

    func testIPadShowsListsBesideDetailsAndKeepsQuickEntryReachable() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Requires an iPad simulator") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["MONEYTRACK_TEST_TODAY"] = "2026-01-15"
        app.launch()

        let setup = app.buttons["budget.setup"]
        XCTAssertTrue(setup.waitForExistence(timeout: 10))
        XCTAssertLessThan(app.frame.width, app.frame.height)
        setup.tap()
        let annualBudget = app.textFields["budget.annual"]
        XCTAssertTrue(annualBudget.waitForExistence(timeout: 5))
        annualBudget.tap(); annualBudget.typeText("1200")
        app.buttons["budget.save"].tap()
        let addCategory = app.buttons["category.add"]
        XCTAssertTrue(addCategory.waitForExistence(timeout: 5)); addCategory.tap()
        app.textFields["category.name"].tap(); app.textFields["category.name"].typeText("Food")
        app.textFields["category.annual"].tap(); app.textFields["category.annual"].typeText("600")
        app.buttons["category.save"].tap()
        app.navigationBars["Yearly Plan"].buttons["Close"].tap()

        tapTab("Expenses", in: app)
        let add = app.buttons["expense.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        let quick = app.textFields["expense.quick-entry"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        quick.tap(); quick.typeText("12.50 Coffee Food")
        XCTAssertEqual(app.buttons["expense.quick-category"].value as? String, "Food")
        let popover = XCTAttachment(screenshot: app.screenshot())
        popover.name = "iPad Quick Entry"
        popover.lifetime = .keepAlways
        self.add(popover)
        app.buttons["expense.quick-save"].tap()

        let booking = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "expense-row-")).firstMatch
        XCTAssertTrue(booking.waitForExistence(timeout: 5)); booking.tap()
        let expenseDetail = app.navigationBars["Expense"]
        XCTAssertTrue(expenseDetail.waitForExistence(timeout: 5))
        XCTAssertLessThan(booking.frame.midX, expenseDetail.frame.midX)
        XCTAssertTrue(add.isHittable)

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        wait(for: [landscape], timeout: 8)
        XCTAssertTrue(expenseDetail.isHittable)
        XCTAssertLessThan(booking.frame.midX, expenseDetail.frame.midX)

        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width < app.frame.height
        }, object: nil)
        wait(for: [portrait], timeout: 8)

        tapTab("Budget", in: app)
        let food = app.buttons["category-Food"]
        XCTAssertTrue(food.waitForExistence(timeout: 5)); food.tap()
        let categoryDetail = app.navigationBars["Food"]
        XCTAssertTrue(categoryDetail.waitForExistence(timeout: 5))
        XCTAssertLessThan(food.frame.midX, categoryDetail.frame.midX)
        let budget = XCTAttachment(screenshot: app.screenshot())
        budget.name = "iPad budget and category detail"
        budget.lifetime = .keepAlways
        self.add(budget)
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Coffee")).firstMatch.tap()
        XCTAssertTrue(expenseDetail.waitForExistence(timeout: 5))
        XCTAssertTrue(food.isHittable)

        tapTab("Shared", in: app)
        XCTAssertTrue(app.navigationBars["Shared"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sign in to share"].exists)
    }

    private func tapTab(_ title: String, in app: XCUIApplication) {
        if UIDevice.current.userInterfaceIdiom == .pad {
            // The native top bar exposes overlapping accessibility elements for each tab.
            let tab = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            for _ in 0..<2 where !tab.isSelected {
                tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            XCTAssertTrue(tab.isSelected)
        } else {
            app.tabBars.buttons[title].tap()
        }
    }

    func testPrivacyNoticeIsAvailableWithoutSigningIn() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["MONEYTRACK_TEST_TODAY"] = "2026-01-15"
        app.launch()
        app.buttons["account.open"].tap()
        let privacy = app.buttons["account.privacy"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 5)); privacy.tap()
        XCTAssertTrue(app.navigationBars["Privacy"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["privacy.summary"].exists)
        XCTAssertTrue(app.staticTexts["privacy.summary"].label.contains("does not sell"))
        let picture = XCTAttachment(screenshot: app.screenshot())
        picture.name = "Spendie Privacy available before sign-in"; picture.lifetime = .keepAlways; add(picture)
        XCTAssertFalse(app.staticTexts["Privacy information unavailable"].exists)
    }

    func testNativeMonthPickerSelectionCancellationAndYearBoundaryArrows() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["MONEYTRACK_TEST_TODAY"] = "2026-01-15"
        app.launch()
        let heading = app.buttons["budget.month"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        heading.tap()
        XCTAssertTrue(app.buttons["month.done"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.pickerWheels.count, 2)
        let january = app.pickerWheels.matching(NSPredicate(format: "value CONTAINS %@", "January")).firstMatch
        let year = app.pickerWheels.matching(NSPredicate(format: "value CONTAINS %@", "2026")).firstMatch
        XCTAssertTrue(january.exists); XCTAssertTrue(year.exists)
        year.adjust(toPickerWheelValue: "2025")
        january.adjust(toPickerWheelValue: "December")
        let picture = XCTAttachment(screenshot: app.screenshot())
        picture.name = "Native month and year picker"; picture.lifetime = .keepAlways; add(picture)
        app.buttons["month.done"].tap()
        XCTAssertTrue(heading.label.contains("December 2025"))
        app.buttons["month.next"].tap()
        XCTAssertTrue(heading.label.contains("January 2026"))
        app.buttons["month.previous"].tap()
        XCTAssertTrue(heading.label.contains("December 2025"))
        heading.tap()
        let december = app.pickerWheels.matching(NSPredicate(format: "value CONTAINS %@", "December")).firstMatch
        december.adjust(toPickerWheelValue: "February")
        app.buttons["month.cancel"].tap()
        XCTAssertTrue(heading.label.contains("December 2025"))
        app.tabBars.buttons["Expenses"].tap()
        XCTAssertTrue(heading.label.contains("December 2025"))
        heading.tap()
        XCTAssertEqual(app.pickerWheels.count, 2)
        XCTAssertTrue(app.pickerWheels.matching(NSPredicate(format: "value CONTAINS %@", "December")).firstMatch.exists)
        app.buttons["month.cancel"].tap()
    }

    func testTotalFirstUnallocatedBudgetAndReachableEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["MONEYTRACK_TEST_TODAY"] = "2026-01-15"
        app.launch()
        XCTAssertTrue(app.buttons["budget.setup"].waitForExistence(timeout: 10)); app.buttons["budget.setup"].tap()
        XCTAssertFalse(app.buttons["category.add"].exists)
        app.textFields["budget.annual"].tap(); app.textFields["budget.annual"].typeText("1200")
        XCTAssertEqual(app.textFields["budget.annual"].value as? String, "1,200")
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
        XCTAssertFalse(app.textFields["expense.amount"].exists)
        XCTAssertFalse(app.datePickers["expense.date"].exists)
        let quick = app.textFields["expense.quick-entry"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        quick.tap(); quick.typeText("20 euros at Coffee and friends for Food")
        XCTAssertTrue(app.staticTexts["expense.quick-preview"].label.contains("Coffee and friends"))
        let category = app.buttons["expense.quick-category"]
        category.tap()
        XCTAssertTrue(app.buttons["Food"].waitForExistence(timeout: 5))
        app.buttons["No category"].tap()
        quick.tap(); quick.typeText(" ")
        XCTAssertEqual(category.value as? String, "No category")
        XCTAssertTrue(app.buttons["expense.quick-save"].isEnabled)
        let entry = XCTAttachment(screenshot: app.screenshot())
        entry.name = "Compact Quick Entry popover"; entry.lifetime = .keepAlways; self.add(entry)
        app.buttons["expense.quick-save"].tap()
        let addIsReachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: add)
        wait(for: [addIsReachable], timeout: 8)
        let expenses = XCTAttachment(screenshot: app.screenshot())
        expenses.name = "Expenses with compact floating plus"; expenses.lifetime = .keepAlways; self.add(expenses)
        app.tabBars.buttons["Budget"].tap()
        XCTAssertEqual(app.staticTexts["budget.remaining"].value as? String, "€30.00")
        XCTAssertEqual(app.staticTexts["budget.unallocated"].label, "Unallocated this year, €600.00")
        XCTAssertTrue(app.buttons["category-Food"].label.contains("€50.00"))
        XCTAssertTrue(app.buttons["budget.allocate"].exists)
        XCTAssertTrue(app.buttons["budget.unbudgeted"].exists)
        XCTAssertTrue(app.buttons["category-Food"].isHittable, "Category budgets should be visible alongside the main balance without scrolling.")
        XCTAssertFalse(app.buttons["expense.add"].exists)
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "Whole budget with category amounts"; image.lifetime = .keepAlways; self.add(image)
        app.terminate(); app.launchArguments.removeAll { $0 == "--reset-ui-testing-data" }; app.launch()
        XCTAssertTrue(app.buttons["category-Food"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["budget.unallocated"].label, "Unallocated this year, €600.00")
    }
    func testQuickEntryDetailsPreserveParsedValuesAndDismissAfterSaving() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["MONEYTRACK_TEST_TODAY"] = "2026-01-15"
        app.launch()
        app.tabBars.buttons["Expenses"].tap()
        let add = app.buttons["expense.add"]
        add.tap()
        let quick = app.textFields["expense.quick-entry"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        quick.tap(); quick.typeText("12.50 Coffee")
        app.buttons["expense.quick-details"].tap()
        XCTAssertTrue(app.textFields["expense.amount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["expense.amount"].value as? String, "12.50")
        XCTAssertEqual(app.textFields["expense.description"].value as? String, "Coffee")
        XCTAssertTrue(app.datePickers["expense.date"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["expense.currency"].exists)
        app.buttons["expense.save"].tap()
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: add)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.textFields["expense.quick-entry"].exists)
    }

    func testQuickEntryPreviewStaysInPlaceWhenAnAmountContainsATypo() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["MONEYTRACK_TEST_TODAY"] = "2026-01-15"
        app.launch()
        app.tabBars.buttons["Expenses"].tap()
        app.buttons["expense.add"].tap()
        let field = app.textFields["expense.quick-entry"]
        let preview = app.staticTexts["expense.quick-preview"]
        let category = app.buttons["expense.quick-category"]
        let save = app.buttons["expense.quick-save"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.exists)
        XCTAssertTrue(category.exists)
        XCTAssertFalse(save.isEnabled)
        field.tap(); field.typeText("12.50")
        XCTAssertTrue(save.isEnabled)
        let previewFrame = preview.frame
        let categoryFrame = category.frame
        let inputFrame = field.frame
        field.typeText("a")
        XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(preview.label.contains("Last recognized"))
        XCTAssertTrue(preview.label.contains("€12.50"))
        XCTAssertEqual(app.staticTexts["expense.quick-status"].label, "Check amount")
        XCTAssertEqual(preview.frame.minY, previewFrame.minY, accuracy: 1)
        XCTAssertEqual(category.frame.minY, categoryFrame.minY, accuracy: 1)
        XCTAssertEqual(field.frame.minY, inputFrame.minY, accuracy: 1)
        let typo = XCTAttachment(screenshot: app.screenshot())
        typo.name = "Stable Quick Entry while correcting a typo"; typo.lifetime = .keepAlways; add(typo)
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertTrue(save.isEnabled)
        XCTAssertFalse(preview.label.contains("Last recognized"))
        XCTAssertEqual(preview.frame.minY, previewFrame.minY, accuracy: 1)
        field.typeText(" coffee")
        let ready = XCTAttachment(screenshot: app.screenshot())
        ready.name = "Polished Quick Entry ready to save"; ready.lifetime = .keepAlways; add(ready)
        save.tap()
        XCTAssertTrue(app.buttons["expense.add"].waitForExistence(timeout: 5))
        XCTAssertFalse(field.exists)
    }

    func testManualNoCategorySelectionSurvivesDetailsAndOverridesRecognizedCategory() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["MONEYTRACK_TEST_TODAY"] = "2026-01-15"
        app.launch()
        app.buttons["budget.setup"].tap()
        app.textFields["budget.annual"].tap(); app.textFields["budget.annual"].typeText("1200")
        app.buttons["budget.save"].tap()
        app.buttons["category.add"].tap()
        app.textFields["category.name"].tap(); app.textFields["category.name"].typeText("Food")
        app.textFields["category.annual"].tap(); app.textFields["category.annual"].typeText("600")
        app.buttons["category.save"].tap()
        app.navigationBars["Yearly Plan"].buttons["Close"].tap()
        app.tabBars.buttons["Expenses"].tap()
        app.buttons["expense.add"].tap()
        let quick = app.textFields["expense.quick-entry"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        quick.tap(); quick.typeText("10 coffee Food")
        app.buttons["expense.quick-category"].tap()
        app.buttons["No category"].tap()
        app.buttons["expense.quick-details"].tap()
        XCTAssertTrue(app.buttons["expense.category"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["expense.category"].value as? String, "No category")
        app.buttons["expense.save"].tap()
        app.tabBars.buttons["Budget"].tap()
        XCTAssertEqual(app.staticTexts["budget.unallocated"].label, "Unallocated this year, €600.00")
        XCTAssertTrue(app.buttons["category-Food"].label.contains("€50.00"))
    }

    func testTypedCurrencyCodeFitsInlineAndPreservesDetails() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["MONEYTRACK_TEST_TODAY"] = "2026-01-15"
        app.launch()
        app.tabBars.buttons["Expenses"].tap()
        app.buttons["expense.add"].tap()
        let field = app.textFields["expense.quick-entry"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("5 pln coffee")
        let currency = app.buttons["expense.quick-currency"]
        expectation(for: NSPredicate(format: "value == %@", "PLN"), evaluatedWith: currency)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(field.value as? String, "5 pln coffee")
        XCTAssertGreaterThanOrEqual(field.frame.minX, currency.frame.maxX)
        XCTAssertLessThanOrEqual(field.frame.maxX, app.frame.maxX)
        XCTAssertTrue(currency.isHittable)
        let picture = XCTAttachment(screenshot: app.screenshot())
        picture.name = "Quick Entry with a full PLN currency code"; picture.lifetime = .keepAlways; add(picture)
        app.buttons["expense.quick-details"].tap()
        XCTAssertTrue(app.textFields["expense.amount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["expense.amount"].value as? String, "5.00")
        XCTAssertEqual(app.textFields["expense.description"].value as? String, "coffee")
        XCTAssertTrue(app.buttons["expense.currency"].exists)
    }

    func testQuickEntryAdaptsToAccessibilityTextWithoutOverlappingControls() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data", "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["MONEYTRACK_TEST_TODAY"] = "2026-01-15"
        app.launch()
        tapTab("Expenses", in: app)
        app.buttons["expense.add"].tap()
        let field = app.textFields["expense.quick-entry"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("12.50 coffee")
        let currency = app.buttons["expense.quick-currency"]
        let details = app.buttons["expense.quick-details"]
        let save = app.buttons["expense.quick-save"]
        let category = app.buttons["expense.quick-category"]
        XCTAssertGreaterThanOrEqual(details.frame.minY, app.staticTexts["expense.quick-title"].frame.maxY)
        XCTAssertGreaterThanOrEqual(field.frame.minX, currency.frame.maxX)
        XCTAssertGreaterThanOrEqual(field.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(field.frame.maxX, app.frame.maxX)
        let scroll = app.scrollViews["expense.quick-scroll"]
        XCTAssertTrue(scroll.exists)
        if !category.isHittable {
            // Start in the visible sheet, above the keyboard on iPad.
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.27))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.05))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(category.isHittable)
        XCTAssertGreaterThanOrEqual(category.frame.minY, app.staticTexts["expense.quick-preview"].frame.maxY)
        XCTAssertLessThanOrEqual(category.frame.maxY, scroll.frame.maxY)
        let picture = XCTAttachment(screenshot: app.screenshot())
        picture.name = "Quick Entry at the largest accessibility text size"; picture.lifetime = .keepAlways; add(picture)
        if !save.isHittable { scroll.swipeDown() }
        XCTAssertTrue(details.isHittable); XCTAssertTrue(save.isHittable)
        save.tap()
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: app.buttons["expense.add"])
        waitForExpectations(timeout: 5)
    }

    func testQuickEntryCombinedKeyboardUsesRegionalDecimalAndInlineCurrency() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-ui-testing-data", "-AppleLanguages", "(en)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["MONEYTRACK_TEST_TODAY"] = "2026-01-15"
        app.launch()
        app.tabBars.buttons["Expenses"].tap()
        app.buttons["expense.add"].tap()
        let field = app.textFields["expense.quick-entry"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let five = app.buttons["expense.key.5"]
        XCTAssertTrue(five.waitForExistence(timeout: 5))
        five.tap()
        let decimal = app.buttons["expense.key.decimal"]
        XCTAssertTrue(decimal.waitForExistence(timeout: 5))
        for digit in "1234567890" { XCTAssertTrue(app.buttons["expense.key.\(digit)"].exists) }
        XCTAssertEqual(decimal.label, "Decimal comma")
        XCTAssertEqual(five.frame.midY, decimal.frame.midY, accuracy: 1)
        decimal.tap(); five.tap(); app.buttons["expense.key.0"].tap()
        app.buttons["expense.quick-currency"].tap()
        app.buttons["€ · Euro"].tap()
        field.typeText(" rewe")
        XCTAssertEqual(field.value as? String, "5,50€ rewe")
        XCTAssertTrue(app.buttons["expense.quick-save"].isEnabled)
        let picture = XCTAttachment(screenshot: app.screenshot())
        picture.name = "Quick Entry combined number row and letter keyboard"; picture.lifetime = .keepAlways; add(picture)
        app.buttons["expense.quick-save"].tap()
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: app.buttons["expense.add"])
        waitForExpectations(timeout: 5)
    }

}

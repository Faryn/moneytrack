import XCTest
import SwiftUI
import UIKit
@testable import MoneyTrack

final class BudgetTests: XCTestCase {
    @MainActor
    func testOfflineRateRefreshPreservesLastSnapshotAndMarksItCached() async throws {
        let name = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let rates = ExchangeRates(defaults: defaults)
        await rates.refresh(loader: { throw ConnectionError.invalidData })
        XCTAssertNil(rates.snapshot)
        let snapshot = ExchangeRates.Snapshot(date: "2026-11-03", rates: ["USD": "1.25"])
        await rates.refresh(loader: { snapshot })
        await rates.refresh(loader: { throw ConnectionError.invalidData })
        XCTAssertEqual(rates.snapshot?.rates["USD"], "1.25")
        XCTAssertNotNil(rates.message)
        XCTAssertEqual(ExchangeRates(defaults: defaults).snapshot?.date, "2026-11-03")
    }

    @MainActor
    func testECBFeedUsesPublishedDecimalStringsAndRejectsBrokenData() throws {
        let xml = Data("<Envelope><Cube><Cube time='2026-11-03'><Cube currency='USD' rate='1.11790'/><Cube currency='JPY' rate='176.95'/><Cube currency='IDR' rate='20275.02'/></Cube></Cube></Envelope>".utf8)
        let rates = try ExchangeRates.decode(xml)
        XCTAssertEqual(rates.date, "2026-11-03")
        XCTAssertEqual(rates.rates["USD"], "1.11790")
        XCTAssertThrowsError(try ExchangeRates.decode(Data("<invalid>".utf8)))
        XCTAssertThrowsError(try ExchangeRates.decode(Data("<Envelope><Cube time='oops'/></Envelope>".utf8)))
    }

    func testConversionRoundsOnceBeforeSplittingAndRepayment() throws {
        for (original, code, rate, euro, other) in [(Int64(12345), "USD", "1.25", Int64(9876), Int64(4938)), (1, "USD", "2", 1, 0), (1000, "JPY", "150", 667, 333), (15000, "KRW", "1500", 1000, 500), (1000, "ISK", "150", 667, 333)] {
            let conversion = CurrencyConversion(originalAmount: original, originalCurrency: code, rate: rate, rateDate: "2026-11-03", source: "ECB")
            XCTAssertEqual(try conversion.euroCents(), euro)
            let shares = try SharedMath.calculate(amount: euro, split: .half, paidByUser: true)
            XCTAssertEqual(shares.balance, other)
            XCTAssertEqual(shares.personalShare + shares.otherShare, euro)
        }
        XCTAssertEqual(try QuickExpenseParser.parse("1000 JPY sushi", categories: []).amount, 1000)
        XCTAssertEqual(try QuickExpenseParser.parse("20 USD coffee", categories: []).currency, "USD")
        XCTAssertThrowsError(try CurrencyConversion.parse("1.50", currency: "JPY"))
    }

    func testQuickEntryResolvesAcceptedNamesAndNeverFallsBackToPersonalSharing() throws {
        let saskia = SharingConnection(id: UUID(), otherID: UUID(), otherName: "Saskia")
        for phrase in ["5€ rewe shared with saskia", "5€ rewe geteilt mit SASKIA"] {
            let result = try QuickExpenseParser.parse(phrase, categories: [], connections: [saskia])
            XCTAssertEqual(result.amount, 500)
            XCTAssertEqual(result.description, "rewe")
            XCTAssertEqual(result.sharingConnection, saskia)
        }
        let names = [SharingConnection(id: UUID(), otherID: UUID(), otherName: "Saskia Müller"), SharingConnection(id: UUID(), otherID: UUID(), otherName: "Saskia Schmidt")]
        XCTAssertThrowsError(try QuickExpenseParser.parse("5 rewe shared with saskia", categories: [], connections: names))
        XCTAssertThrowsError(try QuickExpenseParser.parse("5 rewe shared with", categories: [], connections: [saskia]))
        XCTAssertThrowsError(try QuickExpenseParser.parse("5 rewe shared with stranger", categories: [], connections: [saskia]))
        XCTAssertEqual(try QuickExpenseParser.parse("5 rewe shared with Saskia Müller", categories: [], connections: names).sharingConnection, names[0])
        XCTAssertNil(try QuickExpenseParser.parse("5 rewe", categories: [], connections: [saskia]).sharingConnection)
    }

    func testCurrencySignsAndLowercaseCodesRemainUnambiguous() throws {
        for (phrase, code, amount) in [("€5.50 coffee", "EUR", Int64(550)), ("5,50€ coffee", "EUR", 550), ("$5.50 coffee", "USD", 550), ("5,50$ coffee", "USD", 550), ("£5.50 coffee", "GBP", 550), ("5,50£ coffee", "GBP", 550), ("5.50 usd coffee", "USD", 550), ("gbp 5.50 coffee", "GBP", 550), ("jpy 1500 sushi", "JPY", 1500)] {
            let result = try QuickExpenseParser.parse(phrase, categories: [])
            XCTAssertEqual(result.currency, code, phrase)
            XCTAssertEqual(result.amount, amount, phrase)
        }
        for phrase in ["5€ USD coffee", "$5 EUR coffee", "£5 USD coffee", "$5 Euro coffee", "¥500 coffee"] {
            XCTAssertThrowsError(try QuickExpenseParser.parse(phrase, categories: []), phrase)
        }
    }

    @MainActor
    func testQuickEntryNumbersAndCurrencyPreserveCaretSelectionAndRegionalDecimal() throws {
        for (region, separator) in [("en_US", "."), ("de_DE", ",")] {
            var input = "1250 coffee"
            let editor = QuickEntryTextEditor()
            let control = QuickEntryTextField(text: Binding(get: { input }, set: { input = $0 }), isFocused: .constant(false), locale: Locale(identifier: region), editor: editor, onSubmit: {})
            let coordinator = control.makeCoordinator()
            let field = UITextField()
            field.text = input
            coordinator.attach(to: field)
            func select(_ start: Int, _ end: Int) throws {
                let a = try XCTUnwrap(field.position(from: field.beginningOfDocument, offset: start))
                let b = try XCTUnwrap(field.position(from: field.beginningOfDocument, offset: end))
                field.selectedTextRange = field.textRange(from: a, to: b)
            }
            try select(2, 2)
            editor.insert(separator)
            XCTAssertEqual(input, "12\(separator)50 coffee")
            try select(5, 5)
            editor.insert("€")
            XCTAssertEqual(input, "12\(separator)50€ coffee")
            try select(5, 6)
            editor.insert("$")
            XCTAssertEqual(input, "12\(separator)50$ coffee")
            try select(5, 6)
            editor.insert("£")
            XCTAssertEqual(input, "12\(separator)50£ coffee")
            let row = try XCTUnwrap(field.inputAccessoryView as? QuickEntryNumberRow)
            let stack = try XCTUnwrap(row.subviews.compactMap { $0 as? UIStackView }.first)
            let buttons = stack.arrangedSubviews.compactMap { $0 as? UIButton }
            XCTAssertEqual(buttons.map { $0.title(for: .normal) }, Array("1234567890").map(String.init) + [separator])
            // Exercise the actual key actions with a selection and a caret next to
            // Unicode text; neither shortcut may move the insertion to the end.
            field.text = "☕️1250 coffee"; input = field.text!
            let prefixLength = "☕️".utf16.count
            try select(prefixLength, prefixLength + 4)
            buttons[4].sendActions(for: .touchUpInside)
            XCTAssertEqual(input, "☕️5 coffee")
            buttons.last!.sendActions(for: .touchUpInside)
            buttons[4].sendActions(for: .touchUpInside)
            buttons[9].sendActions(for: .touchUpInside)
            XCTAssertEqual(input, "☕️5\(separator)50 coffee")
            XCTAssertEqual(try QuickExpenseParser.parse(input, categories: []).amount, 550)
            let updated = QuickEntryTextField(text: Binding(get: { input }, set: { input = $0 }), isFocused: .constant(false), locale: Locale(identifier: region == "en_US" ? "de_DE" : "en_US"), editor: editor, onSubmit: {})
            coordinator.parent = updated
            coordinator.updateSeparator()
            XCTAssertEqual(buttons.last?.title(for: .normal), separator == "." ? "," : ".")
        }
    }

    func testQuickEntryParsesGermanEnglishAndExistingCategories() throws {
        let restaurants = CategoryValue(id: UUID(), name: "Restaurants")
        let groceries = CategoryValue(id: UUID(), name: "Lebensmittel")
        let categories = [restaurants, groceries]
        for text in ["78€, Theodor, restaurants", "EUR 78, Theodor, Restaurants", "78 Euro bei Theodor für Restaurants", "at Theodor 78 euros for Restaurants", "I spent 78 euros at Theodor for Restaurants", "Ich habe 78 Euro bei Theodor für Restaurants bezahlt"] {
            let result = try QuickExpenseParser.parse(text, categories: categories)
            XCTAssertEqual(result.amount, 7800, text)
            XCTAssertEqual(result.description, "Theodor", text)
            XCTAssertEqual(result.categoryID, restaurants.id, text)
        }
        let result = try QuickExpenseParser.parse("12,50 € Bäckerei Lebensmittel", categories: categories)
        XCTAssertEqual(result.amount, 1250)
        XCTAssertEqual(result.description, "Bäckerei")
        XCTAssertEqual(result.categoryID, groceries.id)
        XCTAssertEqual(try QuickExpenseParser.parse("78 Theodor", categories: []).description, "Theodor")
        XCTAssertEqual(try QuickExpenseParser.parse("78 Theodor, Restaurants", categories: []).description, "Theodor, Restaurants")
    }

    func testQuickEntryRejectsAmbiguousOrUnsupportedMoney() {
        for text in ["", "coffee", "0 coffee", "-78 coffee", "78.123 coffee", "20 coffee 30", "2026-11-04 coffee", "78 bhd coffee", "78 Franken Kaffee"] {
            XCTAssertThrowsError(try QuickExpenseParser.parse(text, categories: []), text)
        }
    }

    func testQuickEntryKeepsPreviewThroughTyposWithoutMakingStaleAmountsSaveable() throws {
        var recognition = QuickEntryRecognition()
        for (valid, invalid, amount) in [("12", "12a", Int64(1200)), ("12,50", "12,50x", 1250), ("12.50", "12.50.1", 1250)] {
            recognition.update(valid, categories: [], connections: [])
            XCTAssertEqual(recognition.current?.amount, amount)
            let preview = try XCTUnwrap(recognition.preview)
            recognition.update(invalid, categories: [], connections: [])
            XCTAssertNil(recognition.current, invalid)
            XCTAssertNotNil(recognition.issue, invalid)
            XCTAssertEqual(recognition.preview, preview, invalid)
            recognition.update(valid, categories: [], connections: [])
            XCTAssertEqual(recognition.current?.amount, amount)
            XCTAssertNil(recognition.issue)
        }
        recognition.update(" \n", categories: [], connections: [])
        XCTAssertNil(recognition.current)
        XCTAssertNil(recognition.preview)
        XCTAssertNil(recognition.issue)
    }

    func testQuickEntryNeverSavesCachedPreviewAfterInvalidCurrencyOrSharingEdits() throws {
        let saskia = SharingConnection(id: UUID(), otherID: UUID(), otherName: "Saskia")
        let category = CategoryValue(id: UUID(), name: "Food")
        var recognition = QuickEntryRecognition()
        recognition.update("12 USD coffee Food shared with saskia", categories: [category], connections: [saskia])
        let preview = try XCTUnwrap(recognition.current)
        XCTAssertEqual(preview.currency, "USD")
        XCTAssertEqual(preview.categoryID, category.id)
        XCTAssertEqual(preview.sharingConnection, saskia)
        for text in ["12 USD GBP coffee", "12 USD coffee shared with", "12 USD coffee shared with stranger"] {
            recognition.update(text, categories: [category], connections: [saskia])
            XCTAssertNil(recognition.current, text)
            XCTAssertEqual(recognition.preview, preview, text)
            XCTAssertNotNil(recognition.issue, text)
        }
        recognition.update("12 USD coffee Food shared with saskia", categories: [category], connections: [])
        XCTAssertNil(recognition.current, "Removing an accepted connection must invalidate the current parse.")
    }

    func testGroupedBudgetEntryRemainsExactAcrossLocalesAndEditing() throws {
        for (identifier, grouped, decimal) in [("en_US", "1,234,567.89", "."), ("de_DE", "1.234.567,89", ",")] {
            let locale = Locale(identifier: identifier)
            let raw = "1234567\(decimal)89"
            XCTAssertEqual(Money.groupedBudgetInput(raw, locale: locale), grouped)
            XCTAssertEqual(try Money.parse(Money.budgetInputFromDisplay(grouped, previous: "", locale: locale)), 123_456_789)
            let appended = grouped + "9"
            XCTAssertThrowsError(try Money.parse(Money.budgetInputFromDisplay(appended, previous: raw, locale: locale)))
            XCTAssertEqual(Money.groupedBudgetInput("1234\(decimal)", locale: locale), identifier == "en_US" ? "1,234." : "1.234,")
            XCTAssertEqual(try Money.parse(Money.budgetInputFromDisplay(identifier == "en_US" ? "1,2345" : "1.2345", previous: "1234", locale: locale)), 1_234_500)
        }
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(Money.budgetInputFromDisplay("12,34,56.78", previous: "1234", locale: us), "12,34,56.78")
        XCTAssertThrowsError(try Money.parse(Money.budgetInputFromDisplay("12,34,56.78", previous: "1234", locale: us)))
    }

    func testCurrencyUsesTwoDecimalPlacesAndRoundTripsExactly() throws {
        for localeID in ["en_US", "de_DE"] {
            let locale = Locale(identifier: localeID)
            let separator = locale.decimalSeparator!
            for cents in [Int64(0), 1, 10, 100, 7850, Money.maximum] {
                let input = Money.input(cents, locale: locale)
                XCTAssertEqual(input.components(separatedBy: separator).last?.count, 2)
                XCTAssertEqual(try Money.parse(input, allowZero: true), cents)
                XCTAssertTrue(Money.format(cents, locale: locale).contains(separator + String(format: "%02lld", cents % 100)))
            }
        }
        for invalid in ["1.001", "1,999", "0.009", "1.234,56", "1,234.56"] {
            XCTAssertThrowsError(try Money.parse(invalid))
        }
    }
    private struct Examples: Decodable {
        let version: Int
        let cases: [Example]
    }
    private struct Example: Decodable {
        let id: String
        let year: Int
        let month: Int
        let annual: Int64
        let expenses: [Entry]
        let expected: Result
    }
    private struct Entry: Decodable {
        let day: String
        let amount: Int64
        let personalShare: Int64
    }
    private struct Result: Decodable { let allocation: Int64, carryover: Int64, spent: Int64, remaining: Int64 }

    func testSharedFinancialExamples() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "budget-examples", withExtension: "json"))
        let examples = try JSONDecoder().decode(Examples.self, from: Data(contentsOf: url))
        XCTAssertEqual(examples.version, 1)
        let category = CategoryValue(id: UUID(), name: "Example")
        for example in examples.cases {
            let expenses = try example.expenses.map {
                ExpenseValue(id: UUID(), categoryID: category.id, amount: $0.amount, personalShare: $0.personalShare,
                             description: "", day: try ExpenseDay(iso: $0.day), createdAt: Date(timeIntervalSince1970: 0))
            }
            let result = BudgetCalculator.category(category, month: .init(year: example.year, month: example.month),
                                                   annual: example.annual, expenses: expenses)
            XCTAssertEqual(result.allocation, example.expected.allocation, example.id)
            XCTAssertEqual(result.carryover, example.expected.carryover, example.id)
            XCTAssertEqual(result.spent, example.expected.spent, example.id)
            XCTAssertEqual(result.remaining, example.expected.remaining, example.id)
        }
    }

    func testAllocationPreservesEveryCent() {
        for annual in [Int64(0), 1, 11, 12, 13, 100, 101, 600000, 999999] {
            let allocations = (1...12).map {
                BudgetCalculator.cumulativeAllocation(annual: annual, through: $0)
                    - BudgetCalculator.cumulativeAllocation(annual: annual, through: $0 - 1)
            }
            XCTAssertEqual(allocations.reduce(0, +), annual)
            XCTAssertLessThanOrEqual(allocations.max()! - allocations.min()!, 1)
        }
    }

    func testGermanAndEnglishAmountsRemainExact() throws {
        let amounts: [(String, Int64)] = [("78", 7800), ("78€", 7800), ("78,50", 7850), ("78.50", 7850), ("0,01", 1)]
        for (text, expected) in amounts {
            XCTAssertEqual(try Money.parse(text), expected)
        }
        XCTAssertEqual(try Money.parse("0", allowZero: true), 0)
        for invalid in ["", "-1", "0", "1.234", "1,234", "1e3", "7€8", "NaN", "78oops", "999999999999999999999"] {
            XCTAssertThrowsError(try Money.parse(invalid), invalid)
        }
        for locale in [Locale(identifier: "de_DE"), Locale(identifier: "en_US")] {
            XCTAssertEqual(try Money.parse(Money.input(7850, locale: locale)), 7850)
        }
    }

    func testCalendarDaysAreStrictAndIndependentOfTimeZone() throws {
        XCTAssertThrowsError(try ExpenseDay(iso: "2026-02-29"))
        XCTAssertThrowsError(try ExpenseDay(iso: "2026-02-30"))
        XCTAssertThrowsError(try ExpenseDay(iso: "2026-2-001"))
        XCTAssertThrowsError(try ExpenseDay(iso: "2026-+1-01"))
        XCTAssertThrowsError(try ExpenseDay(iso: "2026-01-+1"))
        XCTAssertEqual(try ExpenseDay(iso: "2024-02-29").iso, "2024-02-29")
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T00:30:00Z"))
        XCTAssertEqual(ExpenseDay(date: instant, timeZone: TimeZone(identifier: "America/Los_Angeles")!).iso, "2026-10-31")
        XCTAssertEqual(ExpenseDay(date: instant, timeZone: TimeZone(identifier: "Asia/Tokyo")!).iso, "2026-11-01")
        XCTAssertEqual(try ExpenseDay(iso: "2026-11-01").iso, "2026-11-01")
    }
}

import Foundation
import Observation

enum LedgerError: LocalizedError {
    case invalidAmount, invalidDate, missingCategory, emptyCategory, duplicateCategory, missingExpense
    case sharedEditingUnavailable, categoryTooLong, descriptionTooLong, allocationsExceedTotal

    var errorDescription: String? {
        switch self {
        case .allocationsExceedTotal: String(localized: "Category allocations exceed the yearly budget. Reduce them or increase the total.")
        case .invalidAmount: String(localized: "Enter a valid amount with at most two decimal places.")
        case .invalidDate: String(localized: "Choose a valid calendar date.")
        case .missingCategory: String(localized: "Choose a category for this expense.")
        case .emptyCategory: String(localized: "Enter a category name.")
        case .duplicateCategory: String(localized: "A category with this name already exists.")
        case .missingExpense: String(localized: "This expense is no longer available.")
        case .categoryTooLong: String(localized: "Use a category name of at most 100 characters.")
        case .descriptionTooLong: String(localized: "Use a description of at most 500 characters.")
        case .sharedEditingUnavailable: String(localized: "Open the shared expense to edit its details.")
        }
    }
}

enum Money {
    static let maximum: Int64 = 999_999_999_99

    static func parse(_ input: String, allowZero: Bool = false) throws -> Int64 {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("€") { text.removeLast(); text = text.trimmingCharacters(in: .whitespaces) }
        let parts = text.replacingOccurrences(of: ",", with: ".")
            .split(separator: ".", omittingEmptySubsequences: false)
        func digits(_ part: Substring) -> Bool {
            !part.isEmpty && part.utf8.allSatisfy { (48...57).contains($0) }
        }
        guard (1...2).contains(parts.count), digits(parts[0]),
              parts.count == 1 || (digits(parts[1]) && parts[1].count <= 2),
              let whole = Int64(parts[0]), whole <= maximum / 100 else { throw LedgerError.invalidAmount }
        let fraction = parts.count == 2 ? Int64(parts[1])! * (parts[1].count == 1 ? 10 : 1) : 0
        let amount = whole * 100 + fraction
        guard amount <= maximum, amount > 0 || (allowZero && amount == 0) else { throw LedgerError.invalidAmount }
        return amount
    }

    static func format(_ amount: Int64, locale: Locale = .current) -> String {
        (Decimal(amount) / 100).formatted(.currency(code: "EUR").precision(.fractionLength(2)).locale(locale))
    }

    static func input(_ amount: Int64, locale: Locale = .current) -> String {
        let separator = locale.decimalSeparator ?? "."
        return "\(amount / 100)\(separator)\(String(format: "%02lld", amount % 100))"
    }

    // The stored editing string stays ungrouped, so the existing exact parser remains authoritative.
    static func groupedBudgetInput(_ input: String, locale: Locale) -> String {
        let parts = input.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "." || $0 == "," })
        guard (1...2).contains(parts.count), !parts[0].isEmpty,
              parts[0].allSatisfy({ $0.isASCII && $0.isNumber }),
              parts.count == 1 || parts[1].allSatisfy({ $0.isASCII && $0.isNumber }) else { return input }
        let digits = String(parts[0])
        let grouping = locale.groupingSeparator ?? ","
        var whole = ""
        for (index, digit) in digits.enumerated() {
            if index > 0 && (digits.count - index).isMultiple(of: 3) { whole += grouping }
            whole.append(digit)
        }
        guard parts.count == 2 else { return whole }
        let decimal = locale.decimalSeparator ?? "."
        return whole + decimal + parts[1]
    }

    static func budgetInputFromDisplay(_ display: String, previous: String, locale: Locale) -> String {
        let grouping = locale.groupingSeparator ?? ","
        let decimal = locale.decimalSeparator ?? "."
        let oldDisplay = groupedBudgetInput(previous, locale: locale)
        // Remove separators introduced by the field; pasted groups must be well formed.
        let integer = display.components(separatedBy: decimal).first ?? display
        let groups = integer.components(separatedBy: grouping)
        let validGroups = groups.count > 1 && (1...3).contains(groups[0].count)
            && groups.dropFirst().allSatisfy { $0.count == 3 && $0.allSatisfy { $0.isASCII && $0.isNumber } }
            && groups[0].allSatisfy { $0.isASCII && $0.isNumber }
        let oldCharacters = Array(oldDisplay), newCharacters = Array(display)
        let prefix = zip(oldCharacters, newCharacters).prefix { pair in pair.0 == pair.1 }.count
        let suffix = zip(oldCharacters.dropFirst(prefix).reversed(), newCharacters.dropFirst(prefix).reversed())
            .prefix { pair in pair.0 == pair.1 }.count
        let inserted = newCharacters.count - prefix - suffix
        let removed = oldCharacters.count - prefix - suffix
        let singleEdit = inserted <= 1 && removed <= 1
        let stripGroups = validGroups || (oldDisplay.contains(grouping) && singleEdit)
        return stripGroups ? display.replacingOccurrences(of: grouping, with: "") : display
    }
}

struct ExpenseDay: Hashable, Codable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year!
        month = components.month!
        day = components.day!
    }

    init(iso: String) throws {
        let fields = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard iso.count == 10, fields.count == 3,
              fields[0].count == 4, fields[1].count == 2, fields[2].count == 2,
              fields.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let year = Int(fields[0]), let month = Int(fields[1]), let day = Int(fields[2]),
              (1900...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            throw LedgerError.invalidDate
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { throw LedgerError.invalidDate }
        self.year = year; self.month = month; self.day = day
    }

    var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var date: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.iso < rhs.iso }
}

struct BudgetMonth: Hashable, Sendable {
    var year: Int
    var month: Int

    init(year: Int, month: Int) { self.year = year; self.month = month }
    init(date: Date) {
        let day = ExpenseDay(date: date)
        year = day.year; month = day.month
    }
    var title: String {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: 15))!
        return date.formatted(.dateTime.month(.wide).year())
    }
    func moved(by offset: Int) -> Self {
        let index = year * 12 + month - 1 + offset
        return Self(year: index / 12, month: index % 12 + 1)
    }
}

struct CategoryValue: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
}

struct QuickExpense: Equatable {
    let amount: Int64
    var currency: String = "EUR"
    var sharingConnection: SharingConnection? = nil
    let description: String
    let categoryID: UUID?
}

// A preview may survive an unfinished edit, but only the current parse can be saved.
struct QuickEntryRecognition {
    private(set) var current: QuickExpense?
    private(set) var preview: QuickExpense?
    private(set) var issue: QuickExpenseError?

    mutating func update(_ text: String, categories: [CategoryValue], connections: [SharingConnection]) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self = Self()
            return
        }
        do {
            let result = try QuickExpenseParser.parse(text, categories: categories, connections: connections)
            current = result
            preview = result
            issue = nil
        } catch {
            current = nil
            issue = error as? QuickExpenseError ?? .amount
        }
    }
}

enum QuickExpenseError: LocalizedError {
    case amount, unsupportedCurrency
    case unknownPerson(String), ambiguousPerson(String), missingPerson
    var errorDescription: String? {
        switch self {
        case .missingPerson: String(localized: "Choose someone to share with.")
        case .unknownPerson(let name): String(localized: "No accepted connection with \(name). Invite them by email from a saved expense first.")
        case .ambiguousPerson(let name): String(localized: "More than one person matches \(name). Use their full name or choose in Details.")
        case .amount: String(localized: "Enter one positive euro amount with at most two decimal places, for example 78,50 €.")
        case .unsupportedCurrency: String(localized: "Use one currency: € or EUR, $ or USD, £ or GBP, or another supported code.")
        }
    }
}

enum QuickExpenseParser {
    private static let sharingPattern = try! NSRegularExpression(pattern: #"(?i)\b(?:shared with|geteilt mit)\s+(.+?)\s*$"#)
    private static let sharingIntentPattern = try! NSRegularExpression(pattern: #"(?i)\b(?:shared with|geteilt mit)\b"#)
    private static let currencyPattern = try! NSRegularExpression(pattern: "(?i)(?<![a-z])(?:\((["EUR"] + CurrencyConversion.currencies).joined(separator: "|")))(?![a-z])")
    private static let foreignCurrencyPattern: NSRegularExpression = {
        let codes = Locale.Currency.isoCurrencies.map(\.identifier).filter { $0 != "EUR" }.joined(separator: "|")
        return try! NSRegularExpression(pattern: "(?i)(?:\\d\\s*[,;]?\\s*(?:\(codes))\\b|\\b(?:\(codes))\\s*\\d|\\b(?:dollars?|pounds?|francs?|yen|yuan|bucks|pfund|franken|kronen|rupien)\\b)")
    }()
    private static let amountPattern = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}.,+\-])(?:(?:€|(?i:eur(?:os?)?))\s*)?(\d+(?:[.,]\d+)?)(?:\s*(?:€|(?i:eur(?:os?)?)))?(?![\p{L}\p{N}])"#)
    static func parse(_ originalInput: String, categories: [CategoryValue], connections: [SharingConnection] = []) throws -> QuickExpense {
        guard !originalInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw QuickExpenseError.amount }
        var input = originalInput
        var sharingConnection: SharingConnection?
        if let match = sharingPattern.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
           let nameRange = Range(match.range(at: 1), in: input), let clauseRange = Range(match.range, in: input) {
            let name = input[nameRange].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            func normalized(_ value: String) -> String {
                value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                    .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
            let key = normalized(name)
            let matches = connections.filter {
                let full = normalized($0.otherName)
                return full == key || full.split(separator: " ").first.map(String.init) == key
            }
            guard !matches.isEmpty else { throw QuickExpenseError.unknownPerson(name) }
            guard matches.count == 1 else { throw QuickExpenseError.ambiguousPerson(name) }
            sharingConnection = matches[0]
            input.removeSubrange(clauseRange)
        } else if sharingIntentPattern.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) != nil {
            throw QuickExpenseError.missingPerson
        }
        let currencyMatches = currencyPattern.matches(in: input, range: NSRange(input.startIndex..., in: input))
        guard currencyMatches.count <= 1 else { throw QuickExpenseError.unsupportedCurrency }
        let symbols: [Unicode.Scalar: String] = ["€": "EUR", "$": "USD", "£": "GBP"]
        var currencies = Set<String>()
        for scalar in input.unicodeScalars where scalar.properties.generalCategory == .currencySymbol {
            guard let code = symbols[scalar] else { throw QuickExpenseError.unsupportedCurrency }
            currencies.insert(code)
        }
        if let match = currencyMatches.first, let range = Range(match.range, in: input) {
            currencies.insert(String(input[range]).uppercased())
            input.replaceSubrange(range, with: "€")
        }
        guard currencies.count <= 1 else { throw QuickExpenseError.unsupportedCurrency }
        let currency = currencies.first ?? "EUR"
        input = input.replacingOccurrences(of: "$", with: "€").replacingOccurrences(of: "£", with: "€")
        let range = NSRange(input.startIndex..., in: input)
        guard !input.unicodeScalars.contains(where: { $0.properties.generalCategory == .currencySymbol && $0 != "€" }),
              foreignCurrencyPattern.firstMatch(in: input, range: range) == nil else { throw QuickExpenseError.unsupportedCurrency }
        let matches = amountPattern.matches(in: input, range: range)
        guard matches.count == 1, let amountRange = Range(matches[0].range(at: 1), in: input),
              let matchRange = Range(matches[0].range, in: input),
              let amount = try? CurrencyConversion.parse(String(input[amountRange]), currency: currency) else { throw QuickExpenseError.amount }
        if currency != "EUR", input[matchRange].range(of: #"(?i)eur(?:os?)?"#, options: .regularExpression) != nil {
            throw QuickExpenseError.unsupportedCurrency
        }
        var remainder = input
        remainder.replaceSubrange(matchRange, with: " ")
        guard !remainder.contains(where: { $0.isNumber }) else { throw QuickExpenseError.amount }
        let trim = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        remainder = remainder.trimmingCharacters(in: trim)
        for prefix in ["i spent ", "i paid ", "spent ", "paid ", "ich habe ", "habe "] where remainder.lowercased().hasPrefix(prefix) {
            remainder.removeFirst(prefix.count)
            remainder = remainder.trimmingCharacters(in: trim)
            break
        }
        for suffix in [" bezahlt", " ausgegeben"] where remainder.lowercased().hasSuffix(suffix) {
            remainder.removeLast(suffix.count)
            remainder = remainder.trimmingCharacters(in: trim)
            break
        }

        // Only an existing category at the end is unambiguous enough to select automatically.
        var categoryID: UUID?
        for category in categories.sorted(by: { $0.name.count > $1.name.count }) where !category.name.isEmpty {
            guard let match = remainder.range(of: category.name, options: [.caseInsensitive, .diacriticInsensitive, .backwards]),
                  remainder[match.upperBound...].trimmingCharacters(in: trim).isEmpty,
                  match.lowerBound == remainder.startIndex || !remainder[remainder.index(before: match.lowerBound)].isLetter && !remainder[remainder.index(before: match.lowerBound)].isNumber else { continue }
            categoryID = category.id
            remainder.removeSubrange(match.lowerBound...)
            remainder = remainder.trimmingCharacters(in: trim)
            for word in [" for", " für", " in"] where remainder.lowercased().hasSuffix(word) {
                remainder.removeLast(word.count)
                remainder = remainder.trimmingCharacters(in: trim)
                break
            }
            break
        }
        for prefix in ["at ", "bei "] where remainder.lowercased().hasPrefix(prefix) {
            remainder.removeFirst(prefix.count)
            break
        }
        return QuickExpense(amount: amount, currency: currency, sharingConnection: sharingConnection, description: remainder.trimmingCharacters(in: trim), categoryID: categoryID)
    }
}

struct YearBudgetValue: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let categoryID: UUID
    let year: Int
    var amount: Int64
}

enum BookingKind: String, Codable, CaseIterable, Sendable {
    case expense, income
    var title: String { self == .income ? String(localized: "Income") : String(localized: "Expense") }
}

struct ExpenseValue: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var categoryID: UUID
    var amount: Int64
    var personalShare: Int64
    var description: String
    var day: ExpenseDay
    let createdAt: Date
    var conversion: CurrencyConversion? = nil
    // Optional on the wire so pre-income prepared operations retain their original bytes.
    var kind: BookingKind? = nil
    var isIncome: Bool { kind == .income }
    var budgetSpending: Int64 { isIncome ? 0 : personalShare }
    var signedAmount: Int64 { isIncome ? amount : -personalShare }
}

struct PendingChangeValue: Identifiable, Equatable, Sendable {
    let id: UUID
    let entityID: UUID
    let entity: String
    let action: String
    let sequence: Int64
    let payload: Data
}

struct CategoryBudget: Identifiable, Sendable {
    let category: CategoryValue
    let annual: Int64?
    let allocation: Int64
    let carryover: Int64
    let spent: Int64
    let remaining: Int64
    var id: UUID { category.id }
    var available: Int64 { allocation + carryover }
}

enum BudgetCalculator {
    static func cumulativeAllocation(annual: Int64, through month: Int) -> Int64 {
        precondition(annual >= 0 && (0...12).contains(month))
        return annual / 12 * Int64(month) + min(annual % 12, Int64(month))
    }

    static func category(
        _ category: CategoryValue, month: BudgetMonth, annual: Int64?, expenses: [ExpenseValue]
    ) -> CategoryBudget {
        let relevant = expenses.filter { !$0.isIncome && $0.categoryID == category.id && $0.day.year == month.year }
        let before = relevant.filter { $0.day.month < month.month }.reduce(Int64(0)) { $0 + $1.personalShare }
        let spent = relevant.filter { $0.day.month == month.month }.reduce(Int64(0)) { $0 + $1.personalShare }
        let priorAllocation = cumulativeAllocation(annual: annual ?? 0, through: month.month - 1)
        let allocation = cumulativeAllocation(annual: annual ?? 0, through: month.month) - priorAllocation
        let carryover = priorAllocation - before
        return CategoryBudget(category: category, annual: annual, allocation: allocation,
                              carryover: carryover, spent: spent, remaining: allocation + carryover - spent)
    }
}

struct CurrencyConversion: Codable, Equatable, Sendable {
    let originalAmount: Int64
    let originalCurrency: String
    let rate: String // Foreign major units per EUR; preserve the published decimal string.
    let rateDate: String
    let source: String

    static let currencies = ["AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "GBP", "HKD", "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR"]
    static func digits(_ currency: String) -> Int { ["ISK", "JPY", "KRW"].contains(currency) ? 0 : 2 }
    static func parse(_ text: String, currency: String) throws -> Int64 {
        let cents = try Money.parse(text)
        if digits(currency) == 0 {
            guard cents.isMultiple(of: 100) else { throw LedgerError.invalidAmount }
            return cents / 100
        }
        return cents
    }
    static func input(_ amount: Int64, currency: String) -> String {
        digits(currency) == 0 ? String(amount) : Money.input(amount)
    }
    var originalDisplay: String {
        let divisor: Decimal = Self.digits(originalCurrency) == 0 ? 1 : 100
        return (Decimal(originalAmount) / divisor).formatted(.currency(code: originalCurrency).precision(.fractionLength(Self.digits(originalCurrency))))
    }
    func euroCents() throws -> Int64 {
        guard Self.currencies.contains(originalCurrency), (1...Money.maximum).contains(originalAmount),
              source == "ECB", (try? ExpenseDay(iso: rateDate)) != nil,
              rate.range(of: #"^[0-9]{1,8}(\.[0-9]{1,8})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: rate, locale: Locale(identifier: "en_US_POSIX")), value > 0 else { throw LedgerError.invalidAmount }
        let divisor: Decimal = Self.digits(originalCurrency) == 0 ? 1 : 100
        var raw = Decimal(originalAmount) * 100 / divisor / value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .plain)
        guard rounded >= 1, rounded <= Decimal(Money.maximum) else { throw LedgerError.invalidAmount }
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}

@MainActor @Observable
final class ExchangeRates {
    static let shared = ExchangeRates()
    struct Snapshot: Codable {
        let date: String
        let rates: [String: String]
    }
    private(set) var snapshot: Snapshot?
    private(set) var message: String?
    private(set) var loading = false
    @ObservationIgnored private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snapshot = defaults.data(forKey: "ECBReferenceRates").flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
    }
    func refresh(loader: (() async throws -> Snapshot)? = nil) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let next: Snapshot
            if let loader { next = try await loader() } else {
            let request = URLRequest(url: URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 100_000 else { throw ConnectionError.invalidData }
            next = try Self.decode(data)
            }
            snapshot = next
            defaults.set(try JSONEncoder().encode(next), forKey: "ECBReferenceRates")
            message = nil
        } catch { message = snapshot == nil ? String(localized: "Connect to the internet to download exchange rates before saving this currency.") : String(localized: "Using saved ECB rates. Check the rate date below.") }
    }
    static func decode(_ data: Data) throws -> Snapshot {
        let reader = ECBReader()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = reader
        guard parser.parse(), let date = reader.date, (try? ExpenseDay(iso: date)) != nil, !reader.rates.isEmpty else { throw ConnectionError.invalidData }
        for (currency, rate) in reader.rates {
            _ = try CurrencyConversion(originalAmount: 100_000_000, originalCurrency: currency, rate: rate, rateDate: date, source: "ECB").euroCents()
        }
        return Snapshot(date: date, rates: reader.rates)
    }
    private final class ECBReader: NSObject, XMLParserDelegate {
        var date: String?
        var rates: [String: String] = [:]
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
            if let value = attributes["time"] { date = value }
            if let currency = attributes["currency"], CurrencyConversion.currencies.contains(currency), let rate = attributes["rate"] { rates[currency] = rate }
        }
    }
}

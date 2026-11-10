import SwiftUI
import UIKit

struct CurrencyField: View {
    let title: String
    @Binding var text: String
    let identifier: String
    var focus: FocusState<Bool>.Binding? = nil
    var groupsThousands = false
    var currencyCode = "EUR"
    @Environment(\.locale) private var locale
    @FocusState private var localFocus: Bool
    @State private var budgetFocused = false
    private var isFocused: Bool { focus?.wrappedValue ?? localFocus }
    private var currencyAfterAmount: Bool {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        return !(formatter.string(from: 0) ?? "€0").trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(formatter.currencySymbol)
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                if !groupsThousands || !currencyAfterAmount { currencyLabel }
                if groupsThousands {
                    GroupedBudgetTextField(text: $text, focused: $budgetFocused, locale: locale,
                                           title: title, identifier: identifier)
                        .frame(minWidth: 88)
                } else {
                    TextField(CurrencyConversion.digits(currencyCode) == 0 ? "0" : "0\(locale.decimalSeparator ?? ".")00", text: $text)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        .font(.body).monospacedDigit().frame(minWidth: 88)
                        .focused(focus ?? $localFocus)
                        .accessibilityLabel("\(title), \(currencyCode == "EUR" ? "euros" : currencyCode)")
                        .accessibilityIdentifier(identifier)
                }
                if groupsThousands && currencyAfterAmount { currencyLabel }
            }
        }
        .onChange(of: isFocused) {
            if !isFocused, let cents = try? Money.parse(text, allowZero: true) {
                text = CurrencyConversion.digits(currencyCode) == 0 ? text : Money.input(cents, locale: locale)
            }
        }
        .toolbar {
            if focus == nil && (localFocus || budgetFocused) {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        localFocus = false
                        if budgetFocused { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                    }
                }
            }
        }
    }
    private var currencyLabel: some View {
        Text(groupsThousands ? "€" : currencyCode)
            .font(groupsThousands ? .body : .caption).foregroundStyle(.secondary).accessibilityHidden(true)
    }
}

private struct GroupedBudgetTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let locale: Locale
    let title: String
    let identifier: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .decimalPad
        field.textAlignment = .right
        field.adjustsFontForContentSizeCategory = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.font = .monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        field.placeholder = "0\(locale.decimalSeparator ?? ".")00"
        field.accessibilityLabel = String(localized: "\(title), euros")
        field.accessibilityIdentifier = identifier
        let display = Money.groupedBudgetInput(text, locale: locale)
        if field.text != display { field.text = display }
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: GroupedBudgetTextField
        init(_ parent: GroupedBudgetTextField) { self.parent = parent }
        func textFieldDidBeginEditing(_ textField: UITextField) { parent.focused = true }
        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.focused = false
            if let cents = try? Money.parse(parent.text, allowZero: true) {
                parent.text = Money.input(cents, locale: parent.locale)
            }
        }
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString replacement: String) -> Bool {
            let current = textField.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }
            let edited = current.replacingCharacters(in: swiftRange, with: replacement)
            let raw = Money.budgetInputFromDisplay(edited, previous: parent.text, locale: parent.locale)
            let formatted = Money.groupedBudgetInput(raw, locale: parent.locale)
            let prefix = String(current[..<swiftRange.lowerBound]) + replacement
            let grouping = parent.locale.groupingSeparator ?? ","
            let meaningful = prefix.replacingOccurrences(of: grouping, with: "").count
            var position = formatted.startIndex
            var count = 0
            while position < formatted.endIndex && count < meaningful {
                if !formatted[position...].hasPrefix(grouping) { count += 1 }
                position = formatted.index(after: position)
            }
            let offset = formatted[..<position].utf16.count
            textField.text = formatted
            if let caret = textField.position(from: textField.beginningOfDocument, offset: offset) {
                textField.selectedTextRange = textField.textRange(from: caret, to: caret)
            }
            parent.text = raw
            return false
        }
    }
}

enum AmountColors {
    static let positive = Color("MoneyPositive")
    static let negative = Color("MoneyNegative")
    static func remaining(_ amount: Int64) -> Color {
        amount > 0 ? positive : amount < 0 ? negative : .primary
    }
}

struct ListRowForeground: ShapeStyle {
    let color: Color

    init(_ color: Color) {
        self.color = color
    }

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        environment.backgroundProminence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(color)
    }
}

struct MonthSelector: View {
    @Binding var month: BudgetMonth
    @State private var showingPicker = false
    var body: some View {
        HStack {
            Button("Previous Month", systemImage: "chevron.left") { month = month.moved(by: -1) }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("month.previous")
                .disabled(month.year == 1900 && month.month == 1)
            Spacer(minLength: 8)
            Button { showingPicker = true } label: {
                Text(month.title).font(.headline)
            }
            .accessibilityLabel("Selected month, \(month.title)")
            .accessibilityHint("Choose a month and year")
            .accessibilityIdentifier("budget.month")
            Spacer(minLength: 8)
            Button("Next Month", systemImage: "chevron.right") { month = month.moved(by: 1) }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("month.next")
                .disabled(month.year == 9999 && month.month == 12)
        }
        .buttonStyle(.borderless)
        .sheet(isPresented: $showingPicker) {
            MonthPickerSheet(month: $month)
                .presentationDetents([.height(340), .large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct MonthPickerSheet: View {
    @Binding var month: BudgetMonth
    @State private var draft: BudgetMonth
    @Environment(\.dismiss) private var dismiss

    init(month: Binding<BudgetMonth>) {
        _month = month
        _draft = State(initialValue: month.wrappedValue)
    }
    var body: some View {
        NavigationStack {
            NativeMonthPicker(month: $draft)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Select Month")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.accessibilityIdentifier("month.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { month = draft; dismiss() }.accessibilityIdentifier("month.done")
                    }
                }
        }
    }
}

/// UIKit supplies a real month/year mode; SwiftUI DatePicker also shows a day.
struct NativeMonthPicker: UIViewRepresentable {
    @Binding var month: BudgetMonth
    @Environment(\.locale) private var locale

    static func date(for month: BudgetMonth) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: month.year, month: month.month, day: 15, hour: 12))!
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.preferredDatePickerStyle = .wheels
        picker.datePickerMode = .yearAndMonth
        picker.calendar = Calendar(identifier: .gregorian)
        picker.minimumDate = Self.date(for: BudgetMonth(year: 1900, month: 1))
        picker.maximumDate = Self.date(for: BudgetMonth(year: 9999, month: 12))
        picker.accessibilityIdentifier = "month.picker"
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return picker
    }
    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.parent = self
        if picker.locale != locale { picker.locale = locale }
        if BudgetMonth(date: picker.date) != month { picker.setDate(Self.date(for: month), animated: false) }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIDatePicker, context: Context) -> CGSize? {
        CGSize(width: proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 320, height: 216)
    }
    @MainActor final class Coordinator: NSObject {
        var parent: NativeMonthPicker
        init(_ parent: NativeMonthPicker) { self.parent = parent }
        @objc func changed(_ picker: UIDatePicker) { parent.month = BudgetMonth(date: picker.date) }
    }
}

struct RemainingAmount: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let amount: Int64
    var large = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(amount < 0 ? "Over budget" : "Left this month").foregroundStyle(.secondary)
            Text(Money.format(abs(amount)))
                .font(large ? .largeTitle.weight(.semibold) : .title2.weight(.semibold))
                .foregroundStyle(AmountColors.remaining(amount))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: amount)
                .accessibilityIdentifier(large ? "budget.remaining" : "category.remaining")
                .accessibilityLabel(amount < 0 ? "Over budget" : "Remaining budget")
                .accessibilityValue(Money.format(abs(amount)))
        }
    }
}

struct ExpenseRow: View {
    let expense: ExpenseValue
    let category: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.description.isEmpty ? category : expense.description)
                    .foregroundStyle(.primary)
                Text(expense.isIncome ? String(localized: "Income · \(category)") : category).font(.subheadline).foregroundStyle(.secondary)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                Text((expense.isIncome ? "+" : "") + Money.format(expense.signedAmount))
                    .foregroundStyle(ListRowForeground(expense.isIncome ? AmountColors.positive : expense.personalShare > 0 ? AmountColors.negative : .primary))
                    .monospacedDigit()
                if expense.personalShare != expense.amount {
                    Text("\(Money.format(expense.amount)) total")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Currency menus and keyboard keys share UIKit's current insertion point.
@MainActor final class QuickEntryTextEditor {
    private weak var field: UITextField?
    private var didChange: ((String) -> Void)?

    func attach(to field: UITextField, didChange: @escaping (String) -> Void) {
        self.field = field
        self.didChange = didChange
    }
    func insert(_ value: String) {
        guard let field else { return }
        field.insertText(value)
        didChange?(field.text ?? "")
    }
}

struct QuickEntryTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let locale: Locale
    let editor: QuickEntryTextEditor
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        context.coordinator.attach(to: field)
        field.borderStyle = .none
        field.autocorrectionType = .no
        field.returnKeyType = .done
        field.enablesReturnKeyAutomatically = true
        field.adjustsFontForContentSizeCategory = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.accessibilityLabel = String(localized: "Quick entry")
        field.accessibilityIdentifier = "expense.quick-entry"
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        let font = UIFont.preferredFont(forTextStyle: .title3)
        if field.font != font { field.font = font }
        field.placeholder = String(localized: "78 € Theodor, Restaurants")
        if field.text != text { field.text = text }
        context.coordinator.updateSeparator()
        context.coordinator.updateFocus()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 288, height: max(52, uiView.intrinsicContentSize.height))
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: QuickEntryTextField
        private weak var field: UITextField?
        private weak var numberRow: QuickEntryNumberRow?
        private var focusRequestPending = false
        init(_ parent: QuickEntryTextField) { self.parent = parent }
        func attach(to field: UITextField) {
            self.field = field
            field.delegate = self
            field.addTarget(self, action: #selector(changed), for: .editingChanged)
            parent.editor.attach(to: field) { [weak self] value in self?.parent.text = value }
            let row = QuickEntryNumberRow { [weak self] value in self?.parent.editor.insert(value) }
            numberRow = row
            field.inputAccessoryView = row

            updateSeparator()
        }
        func updateSeparator() {
            let separator = parent.locale.decimalSeparator ?? "."
            numberRow?.decimalSeparator = separator
        }
        func updateFocus() {
            guard let field else { return }
            if parent.isFocused && !field.isFirstResponder && !focusRequestPending {
                focusRequestPending = true
                DispatchQueue.main.async { [weak self, weak field] in
                    guard let self else { return }
                    self.focusRequestPending = false
                    if self.parent.isFocused { field?.becomeFirstResponder() }
                }
            } else if !parent.isFocused && field.isFirstResponder { field.resignFirstResponder() }
        }
        @objc func changed() { parent.text = field?.text ?? "" }
        func textFieldDidBeginEditing(_ textField: UITextField) { if !parent.isFocused { parent.isFocused = true } }
        func textFieldDidEndEditing(_ textField: UITextField) { if parent.isFocused { parent.isFocused = false } }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool { parent.onSubmit(); return false }
    }
}

/// Extra keys for the standard letter keyboard, sharing its full-width surface.
final class QuickEntryNumberRow: UIInputView {
    private let decimalButton: UIButton
    var decimalSeparator = "." {
        didSet {
            guard oldValue != decimalSeparator else { return }
            decimalButton.setTitle(decimalSeparator, for: .normal)
            decimalButton.accessibilityLabel = decimalSeparator == "," ? String(localized: "Decimal comma") : String(localized: "Decimal point")
        }
    }
    init(insert: @escaping (String) -> Void) {
        decimalButton = UIButton(type: .system)
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 56), inputViewStyle: .keyboard)
        autoresizingMask = [.flexibleWidth]
        allowsSelfSizing = true
        accessibilityIdentifier = "expense.number-row"
        let keys = UIStackView()
        keys.axis = .horizontal
        keys.distribution = .fillEqually
        keys.spacing = 4
        keys.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keys)
        for digit in "1234567890" {
            let value = String(digit)
            let button = UIButton(type: .system)
            button.setTitle(value, for: .normal)
            button.accessibilityIdentifier = "expense.key.\(value)"
            button.addAction(UIAction { _ in insert(value) }, for: .touchUpInside)
            keys.addArrangedSubview(button)
        }
        decimalButton.setTitle(decimalSeparator, for: .normal)
        decimalButton.accessibilityLabel = String(localized: "Decimal point")
        decimalButton.accessibilityIdentifier = "expense.key.decimal"
        decimalButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            insert(self.decimalSeparator)
        }, for: .touchUpInside)
        keys.addArrangedSubview(decimalButton)
        for case let button as UIButton in keys.arrangedSubviews {
            // Match the system keyboard: key legends fit their keycaps even when
            // the app uses accessibility text sizes. VoiceOver retains full labels.
            button.titleLabel?.font = UIFont.systemFont(ofSize: 20)
            button.titleLabel?.adjustsFontForContentSizeCategory = false
            button.tintColor = .label
            button.backgroundColor = .secondarySystemGroupedBackground
            button.layer.cornerRadius = 5
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.15
            button.layer.shadowOffset = CGSize(width: 0, height: 1)
            button.layer.shadowRadius = 0
        }
        NSLayoutConstraint.activate([
            keys.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            keys.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            keys.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            keys.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 56) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

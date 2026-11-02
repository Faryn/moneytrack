import SwiftUI

struct CurrencyField: View {
    let title: String
    @Binding var text: String
    let identifier: String
    var focus: FocusState<Bool>.Binding? = nil
    @Environment(\.locale) private var locale
    @FocusState private var localFocus: Bool
    private var isFocused: Bool { focus?.wrappedValue ?? localFocus }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text("EUR").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("0\(locale.decimalSeparator ?? ".")00", text: $text)
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .monospacedDigit().frame(minWidth: 88)
                    .focused(focus ?? $localFocus)
                    .accessibilityLabel("\(title), euros")
                    .accessibilityIdentifier(identifier)
            }
        }
        .onChange(of: isFocused) {
            if !isFocused, let cents = try? Money.parse(text, allowZero: true) {
                text = Money.input(cents, locale: locale)
            }
        }
        .toolbar {
            if focus == nil && localFocus {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { localFocus = false }
                }
            }
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

struct MonthSelector: View {
    @Binding var month: BudgetMonth
    var body: some View {
        HStack {
            Button("Previous Month", systemImage: "chevron.left") { month = month.moved(by: -1) }
                .labelStyle(.iconOnly)
                .disabled(month.year == 1900 && month.month == 1)
            Spacer(minLength: 8)
            Menu {
                ForEach(max(1900, month.year - 2)...min(9999, month.year + 2), id: \.self) { year in
                    Menu(String(year)) {
                        ForEach(1...12, id: \.self) { value in
                            Button(Calendar.current.monthSymbols[value - 1]) {
                                month = BudgetMonth(year: year, month: value)
                            }
                        }
                    }
                }
            } label: {
                Text(month.title).font(.headline)
            }
            .accessibilityLabel("Selected month, \(month.title)")
            .accessibilityIdentifier("budget.month")
            Spacer(minLength: 8)
            Button("Next Month", systemImage: "chevron.right") { month = month.moved(by: 1) }
                .labelStyle(.iconOnly)
                .disabled(month.year == 9999 && month.month == 12)
        }
        .buttonStyle(.borderless)
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
                Text(category).font(.subheadline).foregroundStyle(.secondary)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                Text(Money.format(-expense.personalShare))
                    .foregroundStyle(expense.personalShare > 0 ? AmountColors.negative : .primary).monospacedDigit()
                if expense.personalShare != expense.amount {
                    Text("\(Money.format(expense.amount)) total")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

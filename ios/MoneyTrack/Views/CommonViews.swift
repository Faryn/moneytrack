import SwiftUI

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

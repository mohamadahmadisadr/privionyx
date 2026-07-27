import SwiftUI

/// A dedicated budgeting screen reached from the Dashboard. Each category is a clean,
/// tappable card showing this month's progress; tapping opens a focused editor sheet with a
/// large amount entry and quick presets — so setting a budget feels deliberate rather than
/// like poking at a cramped inline field.
struct BudgetsView: View {
    @Environment(\.dismiss) private var dismiss
    let appState: PrivionyxAppState

    @State private var limits: [String: Double] = [:]
    @State private var editingCategory: ReceiptCategory?
    private let store = MonthlyBudgetStore()

    private var monthSpend: [String: Double] {
        ExpenseAnalytics(context: AssistantContext(receipts: appState.receipts))
            .currentMonthSpendByCategory()
    }

    /// Fixed monthly commitments lead, since those are what people budget first.
    private var orderedCategories: [ReceiptCategory] {
        let fixed = ReceiptCategory.fixedExpenses
        return fixed + ReceiptCategory.allCases.filter { fixed.contains($0) == false }
    }

    var body: some View {
        GlassScreen(wrapsInNavigationStack: false) {
            header
        } content: {
            summaryCard

            VStack(spacing: 10) {
                ForEach(orderedCategories) { budgetCard($0) }
            }

            Text("Budgets reset at the start of each month. The Dashboard flags a category as you approach or exceed its limit.")
                .font(.system(size: 12.5))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                .padding(.top, 2)
        }
        .task { load() }
        .sheet(item: $editingCategory) { category in
            BudgetEditorSheet(
                category: category,
                spent: spent(for: category),
                currentLimit: limit(for: category),
                onSave: { newAmount in setBudget(newAmount, for: category) }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            GlassCircleButton(systemImage: "chevron.left", accessibilityTitle: "Back") {
                dismiss()
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Budgets")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                Text("This month")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
            }

            Spacer()
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        let totalBudget = orderedCategories.reduce(0) { $0 + limit(for: $1) }
        let totalSpent = orderedCategories.reduce(0.0) { sum, category in
            limit(for: category) > 0 ? sum + spent(for: category) : sum
        }
        let fraction = totalBudget > 0 ? totalSpent / totalBudget : 0
        let over = totalSpent > totalBudget && totalBudget > 0
        let tint = over ? PrivionyxTheme.Colors.danger : PrivionyxTheme.Colors.accent

        return HStack(spacing: 18) {
            ring(fraction: fraction, tint: tint, hasBudget: totalBudget > 0)

            VStack(alignment: .leading, spacing: 5) {
                if totalBudget > 0 {
                    Text("\(money(totalSpent)) of \(money(totalBudget))")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(over ? "\(money(totalSpent - totalBudget)) over budget" : "\(money(max(0, totalBudget - totalSpent))) remaining")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(over ? PrivionyxTheme.Colors.danger : PrivionyxTheme.Colors.secondaryInk)
                } else {
                    Text("No budgets yet")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                    Text("Tap a category below to set a monthly limit.")
                        .font(.system(size: 13))
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .privionyxCardStyle()
    }

    private func ring(fraction: Double, tint: Color, hasBudget: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(PrivionyxTheme.Colors.glassFillStrong, lineWidth: 9)

            if hasBudget {
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 0) {
                Text(hasBudget ? "\(Int((fraction * 100).rounded()))%" : "—")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                Text("used")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
            }
        }
        .frame(width: 92, height: 92)
    }

    // MARK: - Category card

    private func budgetCard(_ category: ReceiptCategory) -> some View {
        let limit = limit(for: category)
        let spent = spent(for: category)
        let hasLimit = limit > 0
        let over = hasLimit && spent > limit
        let near = hasLimit && over == false && spent / limit >= 0.8
        let tint: Color = over ? PrivionyxTheme.Colors.danger : (near ? PrivionyxTheme.Colors.warning : PrivionyxTheme.Colors.accent)

        return Button {
            editingCategory = category
        } label: {
            VStack(spacing: 11) {
                HStack(spacing: 12) {
                    Image(systemName: category.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(hasLimit ? tint : PrivionyxTheme.Colors.tertiaryInk)
                        .frame(width: 36, height: 36)
                        .background((hasLimit ? tint : PrivionyxTheme.Colors.tertiaryInk).opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.rawValue)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(PrivionyxTheme.Colors.ink)

                        Text(hasLimit ? "\(money(spent)) of \(money(limit))" : "Tap to set a monthly limit")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 8)

                    if hasLimit {
                        Text(over ? "\(money(spent - limit)) over" : "\(money(limit - spent)) left")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(over ? PrivionyxTheme.Colors.danger : PrivionyxTheme.Colors.secondaryInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
                }

                if hasLimit {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(PrivionyxTheme.Colors.glassFillStrong)
                            Capsule()
                                .fill(tint)
                                .frame(width: max(4, geometry.size.width * min(spent / limit, 1)))
                        }
                    }
                    .frame(height: 7)
                }
            }
            .padding(14)
            .privionyxGlass(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - State

    private func setBudget(_ amount: Double?, for category: ReceiptCategory) {
        store.setBudget(amount, for: category)
        if let amount, amount > 0 {
            limits[category.rawValue] = amount
        } else {
            limits[category.rawValue] = nil
        }
    }

    private func limit(for category: ReceiptCategory) -> Double {
        limits[category.rawValue] ?? 0
    }

    private func spent(for category: ReceiptCategory) -> Double {
        monthSpend[category.rawValue] ?? 0
    }

    private func money(_ amount: Double) -> String {
        PrivionyxCurrencyFormatter.string(for: amount)
    }

    private func load() {
        for category in ReceiptCategory.allCases {
            guard let value = store.budget(for: category) else { continue }
            limits[category.rawValue] = value
        }
    }
}

/// Focused amount editor presented from a category card: a big currency entry with quick
/// presets, this month's spend for context, and Save / Remove actions.
private struct BudgetEditorSheet: View {
    let category: ReceiptCategory
    let spent: Double
    let currentLimit: Double
    let onSave: (Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amount: String = ""
    @FocusState private var isFocused: Bool

    private let presets: [Double] = [100, 250, 500, 1000]

    private var parsed: Double? {
        Double(amount.filter { $0.isNumber || $0 == "." })
    }
    private var currencySymbol: String { Locale.current.currencySymbol ?? "$" }

    var body: some View {
        ZStack {
            PrivionyxTheme.appBackground.ignoresSafeArea()

            VStack(spacing: 20) {
                heading

                amountEntry

                Text("You've spent \(money(spent)) so far this month.")
                    .font(.system(size: 13))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

                presetRow

                Spacer(minLength: 0)

                actions
            }
            .padding(24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            if currentLimit > 0 {
                amount = currentLimit == currentLimit.rounded()
                    ? String(Int(currentLimit))
                    : String(format: "%.2f", currentLimit)
            }
            isFocused = true
        }
    }

    private var heading: some View {
        VStack(spacing: 10) {
            Image(systemName: category.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(PrivionyxTheme.Colors.accent)
                .frame(width: 56, height: 56)
                .background(PrivionyxTheme.Colors.accentSoft, in: Circle())

            Text(category.rawValue)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(PrivionyxTheme.Colors.ink)

            Text("Monthly budget")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
        }
        .padding(.top, 8)
    }

    private var amountEntry: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(currencySymbol)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

            TextField("0", text: $amount)
                .keyboardType(.decimalPad)
                .font(.system(size: 46, weight: .heavy))
                .foregroundStyle(PrivionyxTheme.Colors.ink)
                .fixedSize()
                .focused($isFocused)
                .accessibilityLabel("\(category.rawValue) monthly budget amount")
        }
        .frame(maxWidth: .infinity)
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(presets, id: \.self) { preset in
                Button {
                    amount = String(Int(preset))
                } label: {
                    Text("\(currencySymbol)\(Int(preset))")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(PrivionyxTheme.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .privionyxGlass(cornerRadius: 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                onSave(parsed)
                dismiss()
            } label: {
                Text("Save Budget")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(PrivionyxTheme.Colors.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            if currentLimit > 0 {
                Button {
                    onSave(nil)
                    dismiss()
                } label: {
                    Text("Remove Budget")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.danger)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func money(_ amount: Double) -> String {
        PrivionyxCurrencyFormatter.string(for: amount)
    }
}

#Preview {
    NavigationStack {
        BudgetsView(appState: PrivionyxAppState.preview)
    }
}

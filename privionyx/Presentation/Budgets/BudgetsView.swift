import SwiftUI

/// A dedicated budgeting screen reached from the Dashboard. Shows this month's progress
/// against every category — fixed commitments like Housing first — with an overall ring and
/// inline editing, so setting and tracking budgets feels like a feature rather than a form.
struct BudgetsView: View {
    @Environment(\.dismiss) private var dismiss
    let appState: PrivionyxAppState

    @State private var inputs: [String: String] = [:]
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

            Text("Budgets reset at the start of each month. Set a limit and the Dashboard will flag the category as you approach or exceed it.")
                .font(.system(size: 12.5))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                .padding(.top, 2)
        }
        .task { load() }
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
                    Text("Set a limit for a category below to start tracking.")
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
        let over = limit > 0 && spent > limit
        let near = limit > 0 && over == false && spent / limit >= 0.8
        let tint: Color = over ? PrivionyxTheme.Colors.danger : (near ? PrivionyxTheme.Colors.warning : PrivionyxTheme.Colors.accent)

        return VStack(spacing: 11) {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(limit > 0 ? tint : PrivionyxTheme.Colors.tertiaryInk)
                    .frame(width: 34, height: 34)
                    .background((limit > 0 ? tint : PrivionyxTheme.Colors.tertiaryInk).opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.rawValue)
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)

                    Text(subtitle(limit: limit, spent: spent, over: over))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(over ? PrivionyxTheme.Colors.danger : PrivionyxTheme.Colors.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 8)

                HStack(spacing: 2) {
                    Text(currencySymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
                    TextField("0", text: binding(for: category))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                        .frame(width: 62)
                        .accessibilityLabel("\(category.rawValue) monthly budget")
                }
            }

            if limit > 0 {
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

    private func subtitle(limit: Double, spent: Double, over: Bool) -> String {
        guard limit > 0 else { return "No budget set" }
        let base = "\(money(spent)) of \(money(limit))"
        if over { return base + " · \(money(spent - limit)) over" }
        return base + " · \(money(limit - spent)) left"
    }

    // MARK: - State

    private func binding(for category: ReceiptCategory) -> Binding<String> {
        Binding(
            get: { inputs[category.rawValue] ?? "" },
            set: { newValue in
                inputs[category.rawValue] = newValue
                store.setBudget(Double(newValue.filter { $0.isNumber || $0 == "." }), for: category)
            }
        )
    }

    private func limit(for category: ReceiptCategory) -> Double {
        Double((inputs[category.rawValue] ?? "").filter { $0.isNumber || $0 == "." }) ?? 0
    }

    private func spent(for category: ReceiptCategory) -> Double {
        monthSpend[category.rawValue] ?? 0
    }

    private var currencySymbol: String { Locale.current.currencySymbol ?? "$" }

    private func money(_ amount: Double) -> String {
        PrivionyxCurrencyFormatter.string(for: amount)
    }

    private func load() {
        for category in ReceiptCategory.allCases {
            guard let value = store.budget(for: category) else { continue }
            inputs[category.rawValue] = value == value.rounded()
                ? String(Int(value))
                : String(format: "%.2f", value)
        }
    }
}

#Preview {
    NavigationStack {
        BudgetsView(appState: PrivionyxAppState(container: .preview))
    }
}

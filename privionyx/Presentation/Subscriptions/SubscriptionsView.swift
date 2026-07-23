import SwiftUI

/// Lists the recurring charges detected from the user's receipts — subscriptions and bills —
/// with their cadence and a combined monthly cost. Each one that maps to a category can be
/// turned into a budget in a tap, which is how a detected rent charge becomes a Housing budget.
struct SubscriptionsView: View {
    @Environment(\.dismiss) private var dismiss
    let appState: PrivionyxAppState

    @State private var budgetedCategories: Set<String> = []
    private let budgetStore = MonthlyBudgetStore()

    private var charges: [RecurringCharge] {
        ExpenseAnalytics(context: AssistantContext(receipts: appState.receipts)).recurringCharges()
    }

    var body: some View {
        GlassScreen(wrapsInNavigationStack: false) {
            header
        } content: {
            if charges.isEmpty {
                emptyState
            } else {
                summaryCard(charges)

                VStack(spacing: 10) {
                    ForEach(charges) { chargeCard($0) }
                }
            }
        }
        .task { loadBudgetedCategories() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            GlassCircleButton(systemImage: "chevron.left", accessibilityTitle: "Back") {
                dismiss()
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Subscriptions")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                Text("Recurring charges")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
            }

            Spacer()
        }
    }

    // MARK: - Summary

    private func summaryCard(_ charges: [RecurringCharge]) -> some View {
        let monthly = charges.reduce(0) { $0 + $1.monthlyEquivalent }

        return HStack(spacing: 16) {
            Image(systemName: "repeat")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(PrivionyxTheme.Colors.accent)
                .frame(width: 52, height: 52)
                .background(PrivionyxTheme.Colors.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("\(money(monthly)) / month")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("Across \(charges.count) recurring \(charges.count == 1 ? "charge" : "charges") · about \(money(monthly * 12))/year")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .privionyxCardStyle()
    }

    // MARK: - Charge card

    private func chargeCard(_ charge: RecurringCharge) -> some View {
        VStack(spacing: 11) {
            HStack(spacing: 12) {
                Image(systemName: ReceiptCategory(rawValue: charge.category)?.icon ?? "creditcard.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.accent)
                    .frame(width: 36, height: 36)
                    .background(PrivionyxTheme.Colors.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(charge.merchant)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                        .lineLimit(1)

                    Text("\(charge.cadence.label) · \(charge.category) · last \(charge.lastDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(money(charge.typicalAmount))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                    Text("\(money(charge.monthlyEquivalent))/mo")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
                }
            }

            budgetAction(for: charge)
        }
        .padding(14)
        .privionyxGlass(cornerRadius: 16)
    }

    /// Offers to turn a recurring charge into a monthly budget for its category, or shows that
    /// one already exists. Hidden when the charge's category can't be mapped.
    @ViewBuilder
    private func budgetAction(for charge: RecurringCharge) -> some View {
        if let category = ReceiptCategory(rawValue: charge.category) {
            if budgetedCategories.contains(category.rawValue) {
                Label("\(category.rawValue) budget set", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.success)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button {
                    budgetStore.setBudget(charge.monthlyEquivalent.rounded(), for: category)
                    budgetedCategories.insert(category.rawValue)
                } label: {
                    Label("Set a \(category.rawValue) budget of \(money(charge.monthlyEquivalent.rounded()))", systemImage: "plus.circle")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 12)
                        .privionyxGlass(cornerRadius: 11)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "repeat")
                .font(.system(size: 26))
                .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
            Text("No recurring charges yet")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PrivionyxTheme.Colors.ink)
            Text("Once a merchant bills you a few times on a regular schedule — a subscription, a bill, rent — it'll show up here.")
                .font(.system(size: 13))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 16)
        .privionyxGlass(cornerRadius: 16)
    }

    // MARK: - Helpers

    private func loadBudgetedCategories() {
        budgetedCategories = Set(
            ReceiptCategory.allCases
                .filter { budgetStore.budget(for: $0) != nil }
                .map(\.rawValue)
        )
    }

    private func money(_ amount: Double) -> String {
        PrivionyxCurrencyFormatter.string(for: amount)
    }
}

#Preview {
    NavigationStack {
        SubscriptionsView(appState: PrivionyxAppState(container: .preview))
    }
}

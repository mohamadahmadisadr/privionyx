import Foundation

nonisolated enum ReceiptCategory: String, CaseIterable, Identifiable, Sendable {
    case housing = "Housing"
    case bills = "Bills"
    case gas = "Gas"
    case grocery = "Grocery"
    case dining = "Dining"
    case travel = "Travel"
    case utilities = "Utilities"
    case health = "Health"
    case entertainment = "Entertainment"
    case shopping = "Shopping"

    var id: String { rawValue }

    /// Fixed monthly commitments (rent, mortgage, loan payments) rather than one-off scans.
    /// Kept as a set so budgeting screens can lead with what recurs every month.
    static let fixedExpenses: [ReceiptCategory] = [.housing, .bills, .utilities]

    var icon: String {
        switch self {
        case .housing:
            "house.fill"
        case .bills:
            "creditcard.fill"
        case .gas:
            "fuelpump.fill"
        case .grocery:
            "cart.fill"
        case .dining:
            "fork.knife"
        case .travel:
            "airplane"
        case .utilities:
            "bolt.fill"
        case .health:
            "heart.fill"
        case .entertainment:
            "play.tv.fill"
        case .shopping:
            "bag.fill"
        }
    }
}

import Foundation

enum ReceiptCategory: String, CaseIterable, Identifiable {
    case gas = "Gas"
    case grocery = "Grocery"
    case dining = "Dining"
    case travel = "Travel"
    case utilities = "Utilities"
    case shopping = "Shopping"

    var id: String { rawValue }

    var icon: String {
        switch self {
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
        case .shopping:
            "bag.fill"
        }
    }
}

#if DEBUG
import Foundation

/// Development-only sample data. Seeded when the app is launched with
/// `-privionyxSampleData`, so the dashboard, category bars, and assistant can be
/// exercised without scanning receipts by hand. Never runs in a release build and
/// never runs without the launch argument.
enum PrivionyxSampleData {
    static let launchArgument = "-privionyxSampleData"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func drafts(relativeTo now: Date = .now) -> [ReceiptDraft] {
        let calendar = Calendar.current

        func date(daysAgo: Int) -> Date {
            calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        }

        let entries: [(String, Double, Double?, Int, ReceiptCategory)] = [
            ("Blue Bottle Coffee", 18.90, 1.24, 0, .dining),
            ("Uber", 24.50, nil, 0, .travel),
            ("Whole Foods Market", 86.32, 4.31, 1, .grocery),
            ("Amazon", 142.99, 8.15, 2, .shopping),
            ("Delta Air Lines", 412.00, nil, 3, .travel),
            ("Shell", 61.40, 3.07, 5, .gas),
            ("Trader Joe's", 34.87, 2.14, 6, .grocery),
            ("Hydro One", 98.20, nil, 9, .utilities),
            ("Sweetgreen", 21.75, 1.42, 11, .dining),
            ("Best Buy", 219.99, 12.30, 14, .shopping)
        ]

        return entries.map { merchant, amount, tax, daysAgo, category in
            ReceiptDraft(
                merchant: merchant,
                amount: amount,
                subtotal: tax.map { amount - $0 },
                tax: tax,
                tip: nil,
                date: date(daysAgo: daysAgo),
                category: category,
                customCategoryName: nil,
                tags: [],
                imageData: nil,
                rawText: nil,
                lineItems: [],
                notes: "",
                status: .reviewed
            )
        }
    }
}
#endif

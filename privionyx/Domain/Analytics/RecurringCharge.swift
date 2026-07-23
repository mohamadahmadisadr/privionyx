import Foundation

/// A merchant that charges on a regular cadence — a subscription, a bill, rent — inferred
/// from the spacing and consistency of its receipts. Pure value type so it can drive an
/// insight, a list, and a "use as budget" suggestion from one detection pass.
struct RecurringCharge: Identifiable, Equatable {
    enum Cadence: String, Equatable {
        case weekly
        case biweekly
        case monthly
        case yearly

        /// How many of this cadence fall in an average month — used to normalise everything
        /// to a comparable "per month" figure.
        var perMonthFactor: Double {
            switch self {
            case .weekly: 30.4 / 7
            case .biweekly: 30.4 / 14
            case .monthly: 1
            case .yearly: 1.0 / 12
            }
        }

        var label: String {
            switch self {
            case .weekly: "Weekly"
            case .biweekly: "Every 2 weeks"
            case .monthly: "Monthly"
            case .yearly: "Yearly"
            }
        }

        static func from(medianDays: Double) -> Cadence? {
            switch medianDays {
            case 5...9: .weekly
            case 12...16: .biweekly
            case 25...35: .monthly
            case 350...380: .yearly
            default: nil
            }
        }
    }

    let merchant: String
    let typicalAmount: Double
    let cadence: Cadence
    let occurrences: Int
    let lastDate: Date
    let category: String

    var id: String { merchant }

    /// The charge expressed as a monthly cost, so weekly and yearly commitments can be summed
    /// and compared on equal footing.
    var monthlyEquivalent: Double { typicalAmount * cadence.perMonthFactor }
}

extension ExpenseAnalytics {
    /// Merchants whose receipts recur at a consistent cadence with a consistent amount —
    /// likely subscriptions or bills. Requires enough occurrences to confirm the rhythm, so a
    /// one-off pair of similar charges isn't mistaken for a subscription.
    func recurringCharges(minimumOccurrences: Int = 3) -> [RecurringCharge] {
        var results: [RecurringCharge] = []

        for group in Dictionary(grouping: receipts, by: \.merchant).values where group.count >= minimumOccurrences {
            let sorted = group.sorted { $0.date < $1.date }

            let intervals = zip(sorted.dropFirst(), sorted).map {
                $0.0.date.timeIntervalSince($0.1.date) / 86_400
            }
            guard intervals.isEmpty == false else { continue }

            let medianInterval = median(intervals)
            guard let cadence = RecurringCharge.Cadence.from(medianDays: medianInterval) else { continue }

            // Intervals must be tight around the median — a missed or extra charge (a large
            // gap) means the rhythm isn't reliable enough to call it recurring.
            guard let minInterval = intervals.min(), let maxInterval = intervals.max(),
                  medianInterval > 0, (maxInterval - minInterval) <= medianInterval * 0.5 else { continue }

            // Amounts must be near-constant — a subscription bills the same each period.
            let amounts = sorted.map(\.amount)
            let meanAmount = amounts.reduce(0, +) / Double(amounts.count)
            guard let minAmount = amounts.min(), let maxAmount = amounts.max(),
                  (maxAmount - minAmount) <= max(meanAmount * 0.15, 2.0) else { continue }

            guard let last = sorted.last else { continue }
            results.append(RecurringCharge(
                merchant: last.merchant,
                typicalAmount: median(amounts),
                cadence: cadence,
                occurrences: sorted.count,
                lastDate: last.date,
                category: last.category
            ))
        }

        return results.sorted { $0.monthlyEquivalent > $1.monthlyEquivalent }
    }

    /// Combined monthly cost of every detected recurring charge.
    func recurringMonthlyTotal(minimumOccurrences: Int = 3) -> Double {
        recurringCharges(minimumOccurrences: minimumOccurrences).reduce(0) { $0 + $1.monthlyEquivalent }
    }

    private func median(_ values: [Double]) -> Double {
        guard values.isEmpty == false else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

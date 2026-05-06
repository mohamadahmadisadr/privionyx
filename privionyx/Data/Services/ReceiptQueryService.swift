import Foundation

struct ReceiptQueryService {
    func makeQuery(
        searchText: String,
        selectedCategory: ReceiptCategory?,
        dateInterval: DateInterval? = nil,
        minimumAmount: Double? = nil,
        maximumAmount: Double? = nil
    ) -> SpendingQuery {
        SpendingQuery(
            category: selectedCategory,
            searchText: searchText.isEmpty ? nil : searchText,
            dateInterval: dateInterval,
            minimumAmount: minimumAmount,
            maximumAmount: maximumAmount
        )
    }

    func total(for receipts: [ReceiptItem]) -> Double {
        receipts.reduce(0) { $0 + $1.amount }
    }

    func average(for receipts: [ReceiptItem]) -> Double {
        guard receipts.isEmpty == false else { return 0 }
        return total(for: receipts) / Double(receipts.count)
    }

    func topCategory(in receipts: [ReceiptItem]) -> (category: ReceiptCategory, total: Double)? {
        let grouped = Dictionary(grouping: receipts, by: \.category)
            .mapValues { total(for: $0) }

        guard let winner = grouped.max(by: { $0.value < $1.value }) else {
            return nil
        }

        return (winner.key, winner.value)
    }
}

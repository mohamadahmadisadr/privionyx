import Foundation

struct SpendingQuery: Hashable {
    var category: ReceiptCategory?
    var searchText: String?
    var dateInterval: DateInterval?
    var minimumAmount: Double?
    var maximumAmount: Double?
}

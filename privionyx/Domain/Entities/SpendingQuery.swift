import Foundation

struct SpendingQuery: Hashable {
    var category: ReceiptCategory?
    var searchText: String?
    var dateInterval: DateInterval?
    var minimumAmount: Double?
    var maximumAmount: Double?
}

enum ReceiptSortMode: String, Hashable, Sendable {
    case newest
    case oldest
    case largest
    case smallest
}

struct ParsedReceiptData: Hashable {
    var merchant: String
    var amount: Double
    var subtotal: Double?
    var tax: Double?
    var tip: Double?
    var date: Date
    var category: ReceiptCategory
    var rawText: String
    var lineItems: [ReceiptLineItem]
    var notes: String
}

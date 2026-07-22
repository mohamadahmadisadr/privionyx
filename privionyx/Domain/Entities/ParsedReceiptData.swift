import Foundation

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

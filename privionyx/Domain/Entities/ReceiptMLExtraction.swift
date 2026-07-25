import Foundation

nonisolated struct ReceiptMLExtraction: Sendable {
    var merchant: String?
    var amount: Double?
    var subtotal: Double?
    var tax: Double?
    var tip: Double?
    var date: Date?
}

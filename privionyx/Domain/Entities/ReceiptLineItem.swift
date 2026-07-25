import Foundation

nonisolated struct ReceiptLineItem: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var quantity: Int?
    var amount: Double

    init(id: UUID = UUID(), name: String, quantity: Int? = nil, amount: Double) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.amount = amount
    }
}

import Foundation

struct ReceiptLineItem: Identifiable, Hashable, Codable {
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

import Foundation

struct ReceiptItem: Identifiable, Hashable {
    let id: UUID
    let merchant: String
    let amount: Double
    let subtotal: Double?
    let tax: Double?
    let tip: Double?
    let date: Date
    let category: ReceiptCategory
    let customCategoryName: String?
    let tags: [String]
    let imagePath: String?
    let imageData: Data?
    let rawText: String?
    let lineItems: [ReceiptLineItem]
    let notes: String
    let status: ReceiptProcessingStatus

    var displayCategoryName: String {
        let customName = customCategoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return customName.isEmpty ? category.rawValue : customName
    }
}

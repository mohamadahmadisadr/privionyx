import Foundation

/// A saved receipt as the app reads it.
///
/// Deliberately carries the image's *path* and not its bytes. Every receipt the user owns
/// is held in `PrivionyxAppState.receipts` for the lifetime of the app, and a capture is
/// on the order of a megabyte — inlining the bytes here made the app's resident memory grow
/// with the size of the library, to render a list that only ever shows a monogram tile.
/// Load the bytes on demand through `ReceiptImageStore` at the one screen that shows them.
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
    let rawText: String?
    let lineItems: [ReceiptLineItem]
    let notes: String
    let status: ReceiptProcessingStatus

    /// Whether an image was stored for this receipt, answerable without reading it.
    var hasImage: Bool {
        imagePath?.isEmpty == false
    }

    var displayCategoryName: String {
        let customName = customCategoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return customName.isEmpty ? category.rawValue : customName
    }
}

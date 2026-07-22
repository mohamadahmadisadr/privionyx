import Foundation

struct ReceiptDraft: Identifiable, Hashable {
    let id: UUID
    var merchant: String
    var amount: Double
    var subtotal: Double?
    var tax: Double?
    var tip: Double?
    var date: Date
    var category: ReceiptCategory
    var customCategoryName: String?
    var tags: [String]
    var imagePath: String?
    var imageData: Data?
    var rawText: String?
    var lineItems: [ReceiptLineItem]
    var notes: String
    var status: ReceiptProcessingStatus
    /// Totals figures reconciliation computed rather than read off the receipt. Extraction
    /// metadata about this scan, not receipt data, so it is deliberately not persisted.
    var derivedTotals: Set<ReceiptTotalsReconciler.Field>
    var totalsStatus: ReceiptTotalsReconciler.Status

    init(
        id: UUID = UUID(),
        merchant: String = "",
        amount: Double = .zero,
        subtotal: Double? = nil,
        tax: Double? = nil,
        tip: Double? = nil,
        date: Date = .now,
        category: ReceiptCategory = .shopping,
        customCategoryName: String? = nil,
        tags: [String] = [],
        imagePath: String? = nil,
        imageData: Data? = nil,
        rawText: String? = nil,
        lineItems: [ReceiptLineItem] = [],
        notes: String = "",
        status: ReceiptProcessingStatus = .scanned,
        derivedTotals: Set<ReceiptTotalsReconciler.Field> = [],
        totalsStatus: ReceiptTotalsReconciler.Status = .unverified
    ) {
        self.id = id
        self.merchant = merchant
        self.amount = amount
        self.subtotal = subtotal
        self.tax = tax
        self.tip = tip
        self.date = date
        self.category = category
        self.customCategoryName = customCategoryName
        self.tags = tags
        self.imagePath = imagePath
        self.imageData = imageData
        self.rawText = rawText
        self.lineItems = lineItems
        self.notes = notes
        self.status = status
        self.derivedTotals = derivedTotals
        self.totalsStatus = totalsStatus
    }

    init(item: ReceiptItem) {
        self.id = item.id
        self.merchant = item.merchant
        self.amount = item.amount
        self.subtotal = item.subtotal
        self.tax = item.tax
        self.tip = item.tip
        self.date = item.date
        self.category = item.category
        self.customCategoryName = item.customCategoryName
        self.tags = item.tags
        self.imagePath = item.imagePath
        self.imageData = item.imageData
        self.rawText = item.rawText
        self.lineItems = item.lineItems
        self.notes = item.notes
        self.status = item.status
        // A saved receipt carries no memory of how its figures were obtained.
        self.derivedTotals = []
        self.totalsStatus = .unverified
    }

    var receiptItem: ReceiptItem {
        ReceiptItem(
            id: id,
            merchant: merchant,
            amount: amount,
            subtotal: subtotal,
            tax: tax,
            tip: tip,
            date: date,
            category: category,
            customCategoryName: customCategoryName,
            tags: tags,
            imagePath: imagePath,
            imageData: imageData,
            rawText: rawText,
            lineItems: lineItems,
            notes: notes,
            status: status
        )
    }

    var displayCategoryName: String {
        let customName = customCategoryName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return customName.isEmpty ? category.rawValue : customName
    }
}

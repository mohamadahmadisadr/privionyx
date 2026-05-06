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

enum ReceiptCategory: String, CaseIterable, Identifiable {
    case gas = "Gas"
    case grocery = "Grocery"
    case dining = "Dining"
    case travel = "Travel"
    case utilities = "Utilities"
    case shopping = "Shopping"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .gas:
            "fuelpump.fill"
        case .grocery:
            "cart.fill"
        case .dining:
            "fork.knife"
        case .travel:
            "airplane"
        case .utilities:
            "bolt.fill"
        case .shopping:
            "bag.fill"
        }
    }
}

enum ReceiptProcessingStatus: String {
    case scanned = "Scanned"
    case reviewed = "Reviewed"
    case flagged = "Needs Review"
}

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
        status: ReceiptProcessingStatus = .scanned
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

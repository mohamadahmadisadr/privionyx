import CoreData
import Foundation

final class CoreDataReceiptRepository: ReceiptRepository {
    let stack: CoreDataStack
    let fileStorage: ReceiptFileStorage
    /// Records which one-off maintenance steps have run. See `performMaintenance()`.
    let defaults: UserDefaults

    init(
        stack: CoreDataStack,
        fileStorage: ReceiptFileStorage = ReceiptFileStorage(),
        defaults: UserDefaults = .standard
    ) {
        self.stack = stack
        self.fileStorage = fileStorage
        self.defaults = defaults
    }

    /// A read, and only a read. The legacy image-blob conversion used to happen here, which
    /// meant a query could mutate rows and save — so any fetch could fail on a write error,
    /// and two concurrent fetches could conflict. It runs in `performMaintenance()` now.
    func fetchReceipts(matching query: SpendingQuery?) async throws -> [ReceiptItem] {
        try await stack.container.performBackgroundTask { context in
            let request = ReceiptManagedObject.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            request.predicate = Self.makePredicate(for: query)

            return try context.fetch(request).map(Self.map)
        }
    }

    func upsertReceipt(_ receipt: ReceiptDraft) async throws {
        try await stack.container.performBackgroundTask { context in
            let request = ReceiptManagedObject.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", receipt.id as CVarArg)

            let existingObject = try context.fetch(request).first
            let object = existingObject ?? ReceiptManagedObject(context: context)
            let storedImagePath: String?

            if let imageData = receipt.imageData, imageData.isEmpty == false {
                storedImagePath = try self.fileStorage.saveImageData(imageData, for: receipt.id, replacing: existingObject?.imagePath)
            } else {
                storedImagePath = existingObject?.imagePath ?? receipt.imagePath
            }

            object.id = receipt.id
            object.merchant = receipt.merchant
            object.amount = receipt.amount
            object.subtotal = receipt.subtotal.map(NSNumber.init(value:))
            object.tax = receipt.tax.map(NSNumber.init(value:))
            object.tip = receipt.tip.map(NSNumber.init(value:))
            object.date = receipt.date
            object.category = receipt.category.rawValue
            object.customCategoryName = receipt.customCategoryName?.trimmingCharacters(in: .whitespacesAndNewlines)
            object.tagsText = receipt.tags.isEmpty ? nil : receipt.tags.joined(separator: "\n")
            object.imagePath = storedImagePath
            object.imageData = nil
            object.rawText = receipt.rawText
            object.lineItemsText = ReceiptLineItemCoder.encode(receipt.lineItems)
            object.notes = receipt.notes
            object.status = receipt.status.rawValue
            if existingObject == nil {
                object.createdAt = .now
            }

            try context.save()
        }
    }

    func deleteReceipt(id: UUID) async throws {
        try await stack.container.performBackgroundTask { context in
            let request = ReceiptManagedObject.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

            guard let object = try context.fetch(request).first else { return }
            let imagePath = object.imagePath

            context.delete(object)
            try context.save()
            try self.fileStorage.deleteImage(at: imagePath)
        }
    }

    private static func makePredicate(for query: SpendingQuery?) -> NSPredicate? {
        guard let query else { return nil }

        var predicates: [NSPredicate] = []

        if let category = query.category {
            predicates.append(NSPredicate(format: "category == %@", category.rawValue))
        }

        if let searchText = query.searchText, searchText.isEmpty == false {
            predicates.append(
                NSCompoundPredicate(
                    orPredicateWithSubpredicates: [
                        NSPredicate(format: "merchant CONTAINS[cd] %@", searchText),
                        NSPredicate(format: "notes CONTAINS[cd] %@", searchText),
                        NSPredicate(format: "customCategoryName CONTAINS[cd] %@", searchText),
                        NSPredicate(format: "tagsText CONTAINS[cd] %@", searchText),
                        NSPredicate(format: "rawText CONTAINS[cd] %@", searchText)
                    ]
                )
            )
        }

        if let dateInterval = query.dateInterval {
            predicates.append(NSPredicate(format: "date >= %@ AND date < %@", dateInterval.start as NSDate, dateInterval.end as NSDate))
        }

        if let minimumAmount = query.minimumAmount {
            predicates.append(NSPredicate(format: "amount >= %lf", minimumAmount))
        }

        if let maximumAmount = query.maximumAmount {
            predicates.append(NSPredicate(format: "amount <= %lf", maximumAmount))
        }

        if predicates.isEmpty {
            return nil
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    /// Maps a row without touching its image. The bytes are read on demand through
    /// `ReceiptImageStore` by the one screen that displays them — see `ReceiptItem`.
    private static func map(_ object: ReceiptManagedObject) -> ReceiptItem {
        ReceiptItem(
            id: object.id,
            merchant: object.merchant,
            amount: object.amount,
            subtotal: object.subtotal?.doubleValue,
            tax: object.tax?.doubleValue,
            tip: object.tip?.doubleValue,
            date: object.date,
            category: ReceiptCategory(rawValue: object.category) ?? .shopping,
            customCategoryName: object.customCategoryName,
            tags: object.tagsText?
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false } ?? [],
            imagePath: object.imagePath,
            rawText: object.rawText,
            lineItems: ReceiptLineItemCoder.decode(from: object.lineItemsText),
            notes: object.notes,
            status: ReceiptProcessingStatus(rawValue: object.status) ?? .scanned
        )
    }
}

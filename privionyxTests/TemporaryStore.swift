import CoreData
import Foundation
@testable import privionyx

/// A SQLite store in a unique temporary directory, so store-level tests never touch the
/// app's real one. Shared by the migration and maintenance suites.
struct TemporaryStore {
    let directory: URL
    let url: URL

    init() {
        directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("PrivionyxStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("Privionyx.sqlite")
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// UserDefaults nobody else shares, for the flags maintenance records.
    static func isolatedDefaults() -> UserDefaults {
        let suiteName = "PrivionyxStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @discardableResult
    func writeReceipt(
        merchant: String,
        amount: Double,
        imageData: Data? = nil,
        using model: NSManagedObjectModel
    ) throws -> UUID {
        let context = try makeContext(using: model)
        let receipt = NSEntityDescription.insertNewObject(forEntityName: "Receipt", into: context)
        let id = Self.populate(receipt, merchant: merchant, amount: amount, imageData: imageData)
        try context.save()
        try detach(context)
        return id
    }

    func merchants(using model: NSManagedObjectModel) throws -> [String] {
        let context = try makeContext(using: model)
        defer { try? detach(context) }

        let request = NSFetchRequest<NSManagedObject>(entityName: "Receipt")
        return try context.fetch(request).compactMap { $0.value(forKey: "merchant") as? String }
    }

    func isCompatible(with model: NSManagedObjectModel) throws -> Bool {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        return model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
    }

    /// Every non-optional attribute in the schema, or the save fails validation.
    @discardableResult
    static func populate(
        _ receipt: NSManagedObject,
        merchant: String,
        amount: Double,
        imageData: Data? = nil
    ) -> UUID {
        let id = UUID()
        receipt.setValue(id, forKey: "id")
        receipt.setValue(merchant, forKey: "merchant")
        receipt.setValue(amount, forKey: "amount")
        receipt.setValue(Date(timeIntervalSince1970: 1_700_000_000), forKey: "date")
        receipt.setValue(ReceiptCategory.shopping.rawValue, forKey: "category")
        receipt.setValue("", forKey: "notes")
        receipt.setValue(ReceiptProcessingStatus.reviewed.rawValue, forKey: "status")
        receipt.setValue(Date(timeIntervalSince1970: 1_700_000_000), forKey: "createdAt")
        // Left nil unless asked for, so a row can be written in the pre-file-storage shape.
        receipt.setValue(imageData, forKey: "imageData")
        return id
    }

    private func makeContext(using model: NSManagedObjectModel) throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        _ = try coordinator.addPersistentStore(type: .sqlite, at: url)

        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    /// Releases the store so the next open — or a migration — isn't blocked by this one.
    private func detach(_ context: NSManagedObjectContext) throws {
        guard let coordinator = context.persistentStoreCoordinator else { return }
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
    }
}

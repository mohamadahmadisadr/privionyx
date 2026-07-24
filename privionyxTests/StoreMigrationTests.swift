import CoreData
import Foundation
import Testing
@testable import privionyx

/// Covers the guarantee that a schema change doesn't cost the user their receipts.
///
/// The model is built in code, so Core Data has no `.momd` bundle to find a source model in
/// and cannot infer a migration by itself — `PrivionyxModelVersion` supplies that, and
/// `CoreDataStack.migrateStoreIfNeeded` drives it. Since no second version has shipped yet,
/// these tests stand one up: a copy of v1 with an extra optional attribute, which is exactly
/// the shape of the next real schema change.
@Suite("Store migration")
struct StoreMigrationTests {
    @Test("A store written by an older schema is migrated, keeping its rows")
    func migratesForwardPreservingData() throws {
        let store = TemporaryStore()
        defer { store.remove() }

        let marker = "Migration-\(UUID().uuidString)"
        try store.writeReceipt(merchant: marker, amount: 31.40, using: PrivionyxModelVersion.v1.model)

        let destination = Self.nextSchema()
        // Precondition: the two models really are incompatible, or the test proves nothing.
        #expect(try store.isCompatible(with: destination) == false)

        try CoreDataStack.migrateStoreIfNeeded(at: store.url, to: destination)

        #expect(try store.isCompatible(with: destination), "store did not migrate to the newer schema")

        let merchants = try store.merchants(using: destination)
        #expect(merchants == [marker], "the receipt did not survive migration")
    }

    @Test("Migrating a store that already matches the schema does nothing")
    func currentSchemaIsLeftAlone() throws {
        let store = TemporaryStore()
        defer { store.remove() }

        let model = PrivionyxModelVersion.current.model
        let marker = "NoOp-\(UUID().uuidString)"
        try store.writeReceipt(merchant: marker, amount: 12.00, using: model)

        // Safe to call on every launch, so it must be a no-op in the common case.
        try CoreDataStack.migrateStoreIfNeeded(at: store.url, to: model)
        try CoreDataStack.migrateStoreIfNeeded(at: store.url, to: model)

        #expect(try store.merchants(using: model) == [marker])
    }

    @Test("Migrating a store that does not exist yet is not an error")
    func absentStoreIsNotAnError() throws {
        let store = TemporaryStore()
        defer { store.remove() }

        try CoreDataStack.migrateStoreIfNeeded(at: store.url, to: PrivionyxModelVersion.current.model)
    }

    @Test("An unreadable store is set aside and the app still launches")
    func corruptStoreRecovers() throws {
        let store = TemporaryStore()
        defer { store.remove() }

        // A file that is not a SQLite database at all — the shape of an interrupted write.
        try Data("not a database".utf8).write(to: store.url)

        let stack = CoreDataStack(storeURL: store.url)

        // Previously this was a fatalError, so the bar is simply that construction returns
        // with a usable context rather than taking the process down.
        #expect(stack.container.persistentStoreCoordinator.persistentStores.isEmpty == false)
        #expect(stack.storeLoadFailure != nil, "a reset store must be reported, not silent")

        // And the replacement is actually writable.
        let context = stack.container.viewContext
        let receipt = NSEntityDescription.insertNewObject(forEntityName: "Receipt", into: context)
        TemporaryStore.populate(receipt, merchant: "Recovered", amount: 5)
        #expect(throws: Never.self) { try context.save() }
    }

    @Test("A healthy store reports no failure")
    func healthyStoreIsSilent() throws {
        let store = TemporaryStore()
        defer { store.remove() }

        let stack = CoreDataStack(storeURL: store.url)
        #expect(stack.storeLoadFailure == nil)
    }

    // MARK: - Helpers

    /// v1 plus one optional attribute — the minimal additive change, and the case lightweight
    /// migration is expected to handle without a mapping model.
    private static func nextSchema() -> NSManagedObjectModel {
        let model = PrivionyxModelVersion.v1.model
        guard let entity = model.entitiesByName["Receipt"] else { return model }

        let attribute = NSAttributeDescription()
        attribute.name = "currencyCode"
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = true

        entity.properties = entity.properties + [attribute]
        return model
    }
}

/// A SQLite store in a unique temporary directory, so tests never touch the app's real one.
private struct TemporaryStore {
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

    func writeReceipt(merchant: String, amount: Double, using model: NSManagedObjectModel) throws {
        let context = try makeContext(using: model)
        let receipt = NSEntityDescription.insertNewObject(forEntityName: "Receipt", into: context)
        Self.populate(receipt, merchant: merchant, amount: amount)
        try context.save()
        try detach(context)
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
    static func populate(_ receipt: NSManagedObject, merchant: String, amount: Double) {
        receipt.setValue(UUID(), forKey: "id")
        receipt.setValue(merchant, forKey: "merchant")
        receipt.setValue(amount, forKey: "amount")
        receipt.setValue(Date(timeIntervalSince1970: 1_700_000_000), forKey: "date")
        receipt.setValue(ReceiptCategory.shopping.rawValue, forKey: "category")
        receipt.setValue("", forKey: "notes")
        receipt.setValue(ReceiptProcessingStatus.reviewed.rawValue, forKey: "status")
        receipt.setValue(Date(timeIntervalSince1970: 1_700_000_000), forKey: "createdAt")
    }

    private func makeContext(using model: NSManagedObjectModel) throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(type: .sqlite, at: url)

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

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

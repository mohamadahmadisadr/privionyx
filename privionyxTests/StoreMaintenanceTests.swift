import CoreData
import Foundation
import Testing
@testable import privionyx

/// One-off cleanup of data left by earlier builds, moved off the read path.
///
/// The two steps are guarded differently on purpose, and these cover both halves of that:
/// the placeholder purge runs once and is flag-guarded, while the image-blob conversion is
/// checked on every launch because a row it misses would have its image become invisible.
@Suite("Store maintenance")
struct StoreMaintenanceTests {
    @Test("An inline image blob is moved out to a file")
    func migratesInlineBlob() async throws {
        let store = TemporaryStore()
        defer { store.remove() }

        let imageBytes = Data(repeating: 0xC3, count: 2_048)
        try store.writeReceipt(
            merchant: "Legacy",
            amount: 10,
            imageData: imageBytes,
            using: PrivionyxModelVersion.current.model
        )

        let fileStorage = ReceiptFileStorage()
        let repository = Self.makeRepository(for: store, fileStorage: fileStorage)
        try await repository.performMaintenance()

        let migrated = try #require(try await repository.fetchReceipts(matching: nil).first)
        defer { try? fileStorage.deleteImage(at: migrated.imagePath) }

        // fetchReceipts no longer falls back to reading the blob, so this is the only way
        // the image stays reachable at all.
        #expect(migrated.hasImage, "the blob was not converted to a file")
        #expect(fileStorage.loadImageData(at: migrated.imagePath) == imageBytes)
    }

    @Test("A blob written after maintenance has already run is still converted")
    func blobConversionIsNotFlagged() async throws {
        let store = TemporaryStore()
        defer { store.remove() }

        let defaults = TemporaryStore.isolatedDefaults()
        let fileStorage = ReceiptFileStorage()

        // First launch, nothing to do.
        try await Self.makeRepository(for: store, fileStorage: fileStorage, defaults: defaults)
            .performMaintenance()

        // A store restored from an old backup would look like this on the next launch.
        let imageBytes = Data(repeating: 0x5A, count: 1_024)
        try store.writeReceipt(
            merchant: "Restored",
            amount: 20,
            imageData: imageBytes,
            using: PrivionyxModelVersion.current.model
        )

        let repository = Self.makeRepository(for: store, fileStorage: fileStorage, defaults: defaults)
        try await repository.performMaintenance()

        let migrated = try #require(try await repository.fetchReceipts(matching: nil).first)
        defer { try? fileStorage.deleteImage(at: migrated.imagePath) }

        #expect(migrated.hasImage, "conversion must not be skipped on later launches")
        #expect(fileStorage.loadImageData(at: migrated.imagePath) == imageBytes)
    }

    @Test("Placeholder rows from early builds are removed")
    func purgesPlaceholders() async throws {
        let store = TemporaryStore()
        defer { store.remove() }

        let model = PrivionyxModelVersion.current.model
        try store.writeReceipt(merchant: "Lorem Ipsum Dolor Sit Amet", amount: 1, using: model)
        try store.writeReceipt(merchant: "lorem ipsum placeholder", amount: 2, using: model)

        let repository = Self.makeRepository(for: store)
        try await repository.performMaintenance()

        #expect(try await repository.fetchReceipts(matching: nil).isEmpty)
    }

    /// The predicate once matched real merchant names and generic notes, which deleted
    /// people's own receipts on relaunch. This is the regression guard.
    @Test("Genuine receipts are never mistaken for placeholders")
    func keepsRealReceipts() async throws {
        let store = TemporaryStore()
        defer { store.remove() }

        let model = PrivionyxModelVersion.current.model
        let real = ["Whole Foods Market", "Blue Bottle Coffee", "Target", "Lorena's Bakery"]
        for merchant in real {
            try store.writeReceipt(merchant: merchant, amount: 5, using: model)
        }

        let repository = Self.makeRepository(for: store)
        try await repository.performMaintenance()

        let survivors = try await repository.fetchReceipts(matching: nil).map(\.merchant)
        #expect(Set(survivors) == Set(real))
    }

    @Test("The placeholder scan does not run again once it has completed")
    func purgeRunsOnce() async throws {
        let store = TemporaryStore()
        defer { store.remove() }

        let model = PrivionyxModelVersion.current.model
        let defaults = TemporaryStore.isolatedDefaults()

        try await Self.makeRepository(for: store, defaults: defaults).performMaintenance()

        // Nothing writes placeholders any more, so this can only arrive by test. Its
        // survival is what proves the scan was skipped rather than re-run.
        try store.writeReceipt(merchant: "Lorem Ipsum Dolor Sit Amet", amount: 1, using: model)

        let repository = Self.makeRepository(for: store, defaults: defaults)
        try await repository.performMaintenance()

        #expect(try await repository.fetchReceipts(matching: nil).count == 1)
    }

    // MARK: - Helpers

    private static func makeRepository(
        for store: TemporaryStore,
        fileStorage: ReceiptFileStorage = ReceiptFileStorage(),
        defaults: UserDefaults = TemporaryStore.isolatedDefaults()
    ) -> CoreDataReceiptRepository {
        CoreDataReceiptRepository(
            stack: CoreDataStack(storeURL: store.url),
            fileStorage: fileStorage,
            defaults: defaults
        )
    }
}

import CoreData
import Foundation

/// `@unchecked Sendable`, and only just: the container is handed to background contexts by
/// design, and `viewContext` is bound to the main queue and read only from the main actor.
/// `NSPersistentContainer` carries no `Sendable` conformance to lean on, so the claim is
/// stated here rather than inferred. Everything else on this type is immutable — the loading
/// steps are static so the failure message can be a `let` decided once, in `init`, rather
/// than a `var` the annotation would have to cover as well.
nonisolated final class CoreDataStack: @unchecked Sendable {
    let container: NSPersistentContainer

    /// Set when the on-disk store could not be opened and the app is running on a
    /// replacement. Nil on a normal launch. Surfaced rather than swallowed, because it means
    /// the receipts on screen are not the ones the user saved.
    let storeLoadFailure: String?

    /// - Parameter storeURL: Overrides the on-disk location. Defaults to the app's real
    ///   store; tests point it at a temporary file so they can exercise migration and
    ///   recovery without touching the user's data.
    init(inMemory: Bool = false, storeURL: URL? = nil) {
        let model = PrivionyxModelVersion.current.model
        let container = NSPersistentContainer(name: "PrivionyxModel", managedObjectModel: model)
        self.container = container

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.url = URL(fileURLWithPath: "/dev/null")
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
            _ = Self.load(container)
            storeLoadFailure = nil
        } else {
            let storeURL = storeURL ?? Self.storeURL()

            // Run before loading. A programmatic model gives Core Data no version bundle to
            // find a source model in, so it cannot do this on its own however the store
            // description is configured.
            do {
                try Self.migrateStoreIfNeeded(at: storeURL, to: model)
            } catch {
                // Not fatal on its own — the store may still open, and if it does the message
                // is dropped below. If it doesn't, recovery takes over and names this cause.
            }

            container.persistentStoreDescriptions = [Self.description(for: storeURL)]

            if let error = Self.load(container) {
                storeLoadFailure = Self.recover(container, from: error, storeURL: storeURL)
            } else {
                storeLoadFailure = nil
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        // `NSMergeByPropertyObjectTrumpMergePolicy` is a global `var` of type `Any` in the
        // Core Data overlay, which Swift 6 refuses as shared mutable state. Same policy, as
        // the typed class property.
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }

    // MARK: - Loading

    private static func description(for storeURL: URL) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        // Loading synchronously keeps `load()` able to report its error, and keeps a
        // half-initialised stack from being handed out.
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        return description
    }

    private static func load(_ container: NSPersistentContainer) -> Error? {
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        return loadError
    }

    /// Last resort when the store won't open: move it aside and start clean, so a bad file
    /// costs the user their history rather than the ability to launch at all. The previous
    /// behaviour was `fatalError`, which turned any unreadable or unmigratable store into an
    /// unrecoverable crash on every launch.
    private static func recover(
        _ container: NSPersistentContainer,
        from error: Error,
        storeURL: URL
    ) -> String {
        let quarantined = quarantineStore(at: storeURL)

        if load(container) == nil {
            return quarantined == nil
                ? "Your receipt database couldn't be opened and has been reset."
                : """
                  Your receipt database couldn't be opened, so it was set aside and a new one \
                  started. The previous file is kept at \(quarantined!.lastPathComponent).
                  """
        }

        // Even a brand-new store won't open — the device is out of space, or the container
        // isn't writable. Fall back to memory so the app runs and can say so, instead of
        // crash-looping.
        container.persistentStoreDescriptions = [{
            let description = NSPersistentStoreDescription()
            description.url = URL(fileURLWithPath: "/dev/null")
            description.type = NSInMemoryStoreType
            description.shouldAddStoreAsynchronously = false
            return description
        }()]
        _ = load(container)

        return """
            Privionyx can't reach its database (\(error.localizedDescription)). It's running \
            without saving — anything you add now will be lost when you close the app.
            """
    }

    /// Moves an unreadable store aside rather than deleting it, so the data is still there
    /// if it can be salvaged later. A SQLite store is three files and they only mean
    /// anything together, so they move as a set.
    private static func quarantineStore(at url: URL) -> URL? {
        let fileManager = FileManager.default
        let stamp = Int(Date.now.timeIntervalSince1970)
        let quarantineURL = url.deletingLastPathComponent()
            .appendingPathComponent("Unreadable-\(stamp)-\(url.lastPathComponent)")

        var movedAny = false
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }

            do {
                try fileManager.moveItem(at: source, to: URL(fileURLWithPath: quarantineURL.path + suffix))
                movedAny = true
            } catch {
                // Can't preserve it, but it still has to go or the reload hits the same file.
                try? fileManager.removeItem(at: source)
            }
        }

        return movedAny ? quarantineURL : nil
    }

    // MARK: - Migration

    enum MigrationError: LocalizedError {
        /// No shipped version matches the store — written by a newer build, or damaged.
        case unrecognizedStoreVersion

        var errorDescription: String? {
            switch self {
            case .unrecognizedStoreVersion:
                "the file was written by a version of Privionyx this one doesn't recognise"
            }
        }
    }

    /// Brings a store written by an older schema up to `destinationModel`, in place.
    ///
    /// No-ops when the store doesn't exist yet or already matches, so this is safe on every
    /// launch. The migration runs into a temporary store and is swapped in only once it has
    /// succeeded — a failure partway leaves the original untouched rather than half-converted.
    static func migrateStoreIfNeeded(at url: URL, to destinationModel: NSManagedObjectModel) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        guard destinationModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) == false else {
            return
        }

        guard let sourceVersion = PrivionyxModelVersion.version(forStoreMetadata: metadata) else {
            throw MigrationError.unrecognizedStoreVersion
        }

        let sourceModel = sourceVersion.model
        let mapping = try NSMappingModel.inferredMappingModel(
            forSourceModel: sourceModel,
            destinationModel: destinationModel
        )

        let workingURL = url.deletingLastPathComponent()
            .appendingPathComponent("Migrating-\(UUID().uuidString).sqlite")

        try NSMigrationManager(sourceModel: sourceModel, destinationModel: destinationModel)
            .migrateStore(from: url, type: .sqlite, mapping: mapping, to: workingURL, type: .sqlite)

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: destinationModel)
        try coordinator.replacePersistentStore(at: url, withPersistentStoreFrom: workingURL, type: .sqlite)
        try? coordinator.destroyPersistentStore(at: workingURL, type: .sqlite)
    }

    // MARK: - Location

    static func storeURL() -> URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        let directoryURL = baseURL.appendingPathComponent("Privionyx", isDirectory: true)

        if fileManager.fileExists(atPath: directoryURL.path) == false {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL.appendingPathComponent("Privionyx.sqlite")
    }
}

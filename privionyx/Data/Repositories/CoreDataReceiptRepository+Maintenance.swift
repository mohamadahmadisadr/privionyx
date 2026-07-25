import CoreData
import Foundation

extension CoreDataReceiptRepository {
    /// Cleanup of data left by earlier builds, run once at launch before receipts are loaded.
    ///
    /// This used to be spread across the read path: the seed purge ran on every launch, and
    /// the image-blob migration was folded into `fetchReceipts`, which made a query mutate
    /// and save. Both belong here, where they run once, in a known order, before anything
    /// reads.
    func performMaintenance() async throws {
        try await purgeLegacySeedDataIfNeeded()
        try await migrateLegacyImageBlobs()
    }

    // MARK: - Placeholder rows

    private static let seedPurgeKey = "privionyx.legacy-seed-purged"

    /// Removes placeholder rows shipped by very early builds.
    ///
    /// Guarded by a flag because the check is the expensive kind — `CONTAINS[cd]` can't use
    /// an index, so it scans the table — and the consequence of skipping it is only that a
    /// placeholder row survives. Nothing writes these any more, so once they're gone they
    /// cannot come back.
    ///
    /// The predicate MUST only match text no genuine receipt could carry. Earlier versions
    /// also matched real merchant names ("Whole Foods Market", "Target", …) and generic
    /// notes, which silently deleted the user's own scanned receipts on relaunch.
    private func purgeLegacySeedDataIfNeeded() async throws {
        guard defaults.bool(forKey: Self.seedPurgeKey) == false else { return }

        let placeholderMerchants = [
            "LOREM IPSUM DOLOR SIT AMET",
            "Lorem Ipsum Dolor Sit Amet"
        ]

        try await stack.container.performBackgroundTask { context in
            let request = ReceiptManagedObject.fetchRequest()
            request.predicate = NSCompoundPredicate(
                orPredicateWithSubpredicates: [
                    NSPredicate(format: "merchant IN %@", placeholderMerchants),
                    NSPredicate(format: "merchant CONTAINS[cd] %@", "lorem ipsum")
                ]
            )
            // Only the rows are needed, not their contents — this avoids faulting a matched
            // row's image blob and raw text in just to delete it.
            request.includesPropertyValues = false

            let matches = try context.fetch(request)
            matches.forEach(context.delete)

            if context.hasChanges {
                try context.save()
            }
        }

        defaults.set(true, forKey: Self.seedPurgeKey)
    }

    // MARK: - Inline image blobs

    /// Moves images stored inline in the database out to files.
    ///
    /// Deliberately *not* flag-guarded, unlike the purge above. The predicate is narrow and
    /// matches nothing on a store that has already been converted, so running it each launch
    /// costs a query that returns no rows. Skipping it wrongly is not so cheap: `map` no
    /// longer falls back to reading `imageData`, so a row left unconverted would have its
    /// image become permanently invisible. Cheap to check and expensive to miss, so it is
    /// checked every time and heals a store restored from an old backup.
    private func migrateLegacyImageBlobs() async throws {
        try await stack.container.performBackgroundTask { [fileStorage] context in
            let request = ReceiptManagedObject.fetchRequest()
            request.predicate = NSPredicate(format: "imagePath == nil AND imageData != nil")

            let legacy = try context.fetch(request)
            guard legacy.isEmpty == false else { return }

            for object in legacy {
                defer { object.imageData = nil }

                guard let data = object.imageData, data.isEmpty == false else { continue }
                object.imagePath = try fileStorage.saveImageData(data, for: object.id, replacing: nil)
            }

            try context.save()
        }
    }
}

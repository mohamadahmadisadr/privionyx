import CoreData
import Foundation

extension CoreDataReceiptRepository {
    /// Removes placeholder rows shipped by very early builds.
    ///
    /// This runs on every launch, so it MUST only match text no genuine receipt could
    /// carry. Earlier versions also matched real merchant names ("Whole Foods Market",
    /// "Blue Bottle Coffee", "Target", …) and generic notes — which silently deleted the
    /// user's own scanned receipts on relaunch. Those clauses are gone; only unmistakable
    /// lorem-ipsum placeholder text is purged now.
    func purgeLegacySeedData() async throws {
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

            let matches = try context.fetch(request)
            matches.forEach(context.delete)

            if context.hasChanges {
                try context.save()
            }
        }
    }
}

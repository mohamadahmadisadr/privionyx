import CoreData
import Foundation

extension CoreDataReceiptRepository {
    func purgeLegacySeedData() async throws {
        let legacyMerchants = [
            "Shell Downtown",
            "Whole Foods Market",
            "Blue Bottle Coffee",
            "City Power & Water",
            "Target"
        ]
        let legacyNotes = [
            "OCR confidence 96%",
            "Receipt fields reviewed",
            "Tip included",
            "Billing period matched",
            "Category can be refined"
        ]
        let placeholderMerchants = [
            "LOREM IPSUM DOLOR SIT AMET",
            "Lorem Ipsum Dolor Sit Amet"
        ]

        try await stack.container.performBackgroundTask { context in
            let request = ReceiptManagedObject.fetchRequest()
            request.predicate = NSCompoundPredicate(
                orPredicateWithSubpredicates: [
                    NSPredicate(format: "merchant IN %@", legacyMerchants),
                    NSPredicate(format: "notes IN %@", legacyNotes),
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

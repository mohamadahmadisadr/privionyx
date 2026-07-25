import CoreData
import Foundation

/// Explicitly `nonisolated`: the project defaults every unannotated type to the main actor,
/// and a managed object belongs to the queue of the context that fetched it, which for every
/// write in this app is a background one. Under Swift 5's language mode the default was
/// applied and then ignored — rows were being read and written off the main actor by a type
/// the compiler believed was confined to it.
@objc(ReceiptManagedObject)
nonisolated final class ReceiptManagedObject: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var merchant: String
    @NSManaged var amount: Double
    @NSManaged var subtotal: NSNumber?
    @NSManaged var tax: NSNumber?
    @NSManaged var tip: NSNumber?
    @NSManaged var date: Date
    @NSManaged var category: String
    @NSManaged var customCategoryName: String?
    @NSManaged var tagsText: String?
    @NSManaged var imagePath: String?
    @NSManaged var imageData: Data?
    @NSManaged var rawText: String?
    @NSManaged var lineItemsText: String?
    @NSManaged var notes: String
    @NSManaged var status: String
    @NSManaged var createdAt: Date
}

nonisolated extension ReceiptManagedObject {
    @nonobjc static func fetchRequest() -> NSFetchRequest<ReceiptManagedObject> {
        NSFetchRequest<ReceiptManagedObject>(entityName: "Receipt")
    }
}

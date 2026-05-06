import CoreData
import Foundation

@objc(ReceiptManagedObject)
final class ReceiptManagedObject: NSManagedObject {
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

extension ReceiptManagedObject {
    @nonobjc static func fetchRequest() -> NSFetchRequest<ReceiptManagedObject> {
        NSFetchRequest<ReceiptManagedObject>(entityName: "Receipt")
    }
}

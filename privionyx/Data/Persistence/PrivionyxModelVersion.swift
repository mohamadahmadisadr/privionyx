import CoreData
import Foundation

/// Every schema version the app has ever written a store with.
///
/// The model is built in code rather than compiled from a `.xcdatamodeld`, so there is no
/// `.momd` bundle for Core Data to search when a store's version hashes don't match the
/// current model. Lightweight migration infers a mapping *between two models*, and without
/// somewhere to find the source one it cannot run at all — `shouldMigrateStoreAutomatically`
/// has nothing to work with, and the store simply fails to open. This enum is that bundle:
/// it keeps every shipped version reachable so `CoreDataStack` can identify which one wrote
/// a given store and migrate forward from it.
///
/// **To change the schema:** append a case, give it a `model`, and point `current` at it.
/// Never edit a past case. Its entire purpose is to describe a store already sitting on
/// someone's device, and changing it changes the version hashes that identify those stores —
/// which is exactly the failure this type exists to prevent.
enum PrivionyxModelVersion: CaseIterable {
    /// The original schema, shipped before versioning existed. Reproduces what
    /// `CoreDataStack.makeModel()` built, so stores already on disk stay readable.
    case v1

    /// The version the app writes today.
    static let current: PrivionyxModelVersion = .v1

    var model: NSManagedObjectModel {
        switch self {
        case .v1:
            Self.makeV1()
        }
    }

    /// The version a store carrying this metadata was written by, or nil when none matches —
    /// a store from a newer build, or one too damaged to identify.
    static func version(forStoreMetadata metadata: [String: Any]) -> PrivionyxModelVersion? {
        allCases.first {
            $0.model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
        }
    }

    // MARK: - Versions

    private static func makeV1() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let receiptEntity = NSEntityDescription()
        receiptEntity.name = "Receipt"
        receiptEntity.managedObjectClassName = NSStringFromClass(ReceiptManagedObject.self)

        receiptEntity.properties = [
            attribute(name: "id", type: .UUIDAttributeType),
            attribute(name: "merchant", type: .stringAttributeType),
            attribute(name: "amount", type: .doubleAttributeType),
            attribute(name: "subtotal", type: .doubleAttributeType, optional: true),
            attribute(name: "tax", type: .doubleAttributeType, optional: true),
            attribute(name: "tip", type: .doubleAttributeType, optional: true),
            attribute(name: "date", type: .dateAttributeType),
            attribute(name: "category", type: .stringAttributeType),
            attribute(name: "customCategoryName", type: .stringAttributeType, optional: true),
            attribute(name: "tagsText", type: .stringAttributeType, optional: true),
            attribute(name: "imagePath", type: .stringAttributeType, optional: true),
            attribute(name: "imageData", type: .binaryDataAttributeType, optional: true),
            attribute(name: "rawText", type: .stringAttributeType, optional: true),
            attribute(name: "lineItemsText", type: .stringAttributeType, optional: true),
            attribute(name: "notes", type: .stringAttributeType),
            attribute(name: "status", type: .stringAttributeType),
            attribute(name: "createdAt", type: .dateAttributeType)
        ]

        model.entities = [receiptEntity]
        return model
    }

    private static func attribute(name: String, type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }
}

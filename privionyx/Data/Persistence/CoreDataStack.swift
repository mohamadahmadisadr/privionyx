import CoreData
import Foundation

final class CoreDataStack {
    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "PrivionyxModel", managedObjectModel: model)

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.url = URL(fileURLWithPath: "/dev/null")
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        } else {
            let description = NSPersistentStoreDescription(url: Self.storeURL())
            description.type = NSSQLiteStoreType
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            container.persistentStoreDescriptions = [description]
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load persistent stores: \(error.localizedDescription)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private static func storeURL() -> URL {
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

    private static func makeModel() -> NSManagedObjectModel {
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

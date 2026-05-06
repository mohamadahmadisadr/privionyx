import CoreData
import Foundation

struct PrivionyxAppContainer {
    let viewContext: NSManagedObjectContext
    let repository: ReceiptRepository
    let parser: ReceiptParsingService
    let ocrService: VisionOCRService
    let coreMLReceiptExtractionService: CoreMLReceiptExtractionService
    let queryService: ReceiptQueryService
    let merchantRuleService: MerchantRuleService

    let fetchReceiptsUseCase: FetchReceiptsUseCase
    let saveReceiptUseCase: SaveReceiptUseCase
    let deleteReceiptUseCase: DeleteReceiptUseCase

    static func live(inMemory: Bool = false) -> PrivionyxAppContainer {
        let stack = CoreDataStack(inMemory: inMemory)
        let repository = CoreDataReceiptRepository(stack: stack)
        let ocrService = VisionOCRService()
        let coreMLReceiptExtractionService = CoreMLReceiptExtractionService()
        let queryService = ReceiptQueryService()
        let merchantRuleService = MerchantRuleService(defaults: makeDefaults(inMemory: inMemory))
        let parser = ReceiptParsingService(mlExtractor: coreMLReceiptExtractionService)

        return PrivionyxAppContainer(
            viewContext: stack.container.viewContext,
            repository: repository,
            parser: parser,
            ocrService: ocrService,
            coreMLReceiptExtractionService: coreMLReceiptExtractionService,
            queryService: queryService,
            merchantRuleService: merchantRuleService,
            fetchReceiptsUseCase: FetchReceiptsUseCase(repository: repository),
            saveReceiptUseCase: SaveReceiptUseCase(repository: repository),
            deleteReceiptUseCase: DeleteReceiptUseCase(repository: repository)
        )
    }

    private static func makeDefaults(inMemory: Bool) -> UserDefaults {
        guard inMemory else { return .standard }

        let suiteName = "Privionyx.InMemory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

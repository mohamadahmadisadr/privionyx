import CoreData
import Foundation

struct PrivionyxAppContainer {
    let viewContext: NSManagedObjectContext
    let repository: ReceiptRepository
    let parser: any ReceiptParser
    let ocrService: any OCRService
    let imageProcessor: any ReceiptImageProcessing
    let perspectiveService: any ReceiptPerspectiveCorrecting
    let mlExtractor: any ReceiptMLExtractor
    let merchantRuleService: any MerchantRuleProviding

    let fetchReceiptsUseCase: FetchReceiptsUseCase
    let saveReceiptUseCase: SaveReceiptUseCase
    let deleteReceiptUseCase: DeleteReceiptUseCase
    let resolveCategoryUseCase: ResolveCategoryUseCase
    let processReceiptUseCase: ProcessReceiptImageUseCase

    static func live(inMemory: Bool = false) -> PrivionyxAppContainer {
        let stack = CoreDataStack(inMemory: inMemory)
        let repository = CoreDataReceiptRepository(stack: stack)
        let imageProcessor = ReceiptImageProcessor()
        let perspectiveService = ReceiptPerspectiveService(imageProcessor: imageProcessor)
        let ocrService = VisionOCRService(imageProcessor: imageProcessor)
        let mlExtractor = CoreMLReceiptExtractionService()
        let merchantRuleService = MerchantRuleService(defaults: makeDefaults(inMemory: inMemory))
        let parser = ReceiptParsingService(mlExtractor: mlExtractor)
        let resolveCategoryUseCase = ResolveCategoryUseCase(merchantRules: merchantRuleService)
        let processReceiptUseCase = ProcessReceiptImageUseCase(
            ocrService: ocrService,
            parser: parser,
            resolveCategory: resolveCategoryUseCase
        )

        return PrivionyxAppContainer(
            viewContext: stack.container.viewContext,
            repository: repository,
            parser: parser,
            ocrService: ocrService,
            imageProcessor: imageProcessor,
            perspectiveService: perspectiveService,
            mlExtractor: mlExtractor,
            merchantRuleService: merchantRuleService,
            fetchReceiptsUseCase: FetchReceiptsUseCase(repository: repository),
            saveReceiptUseCase: SaveReceiptUseCase(repository: repository),
            deleteReceiptUseCase: DeleteReceiptUseCase(repository: repository),
            resolveCategoryUseCase: resolveCategoryUseCase,
            processReceiptUseCase: processReceiptUseCase
        )
    }

    static var preview: PrivionyxAppContainer {
        .live(inMemory: true)
    }

    private static func makeDefaults(inMemory: Bool) -> UserDefaults {
        guard inMemory else { return .standard }

        let suiteName = "Privionyx.InMemory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

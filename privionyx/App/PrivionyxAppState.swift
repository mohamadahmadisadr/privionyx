import Observation
import CoreData
import Foundation

@MainActor
@Observable
final class PrivionyxAppState {
    let container: PrivionyxAppContainer
    private var hasCompletedInitialLoad = false

    private(set) var receipts: [ReceiptItem] = []
    private(set) var receiptsVersion = 0
    private(set) var isBootstrapping = false
    private(set) var isLaunching = false
    private(set) var launchProgress: Double = 0
    private(set) var launchStatusText = "Preparing app..."
    var lastErrorMessage: String?

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    init(container: PrivionyxAppContainer) {
        self.container = container
    }

    func bootstrapIfNeeded() async {
        guard isBootstrapping == false, receipts.isEmpty else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        do {
            try await container.repository.purgeLegacySeedData()
            try await loadReceipts()
            try await seedSampleDataIfRequested()
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        // Reported after loading rather than before, so it isn't overwritten by a load error
        // and so the user sees it against the receipts actually on screen. A reset store is
        // not something to discover by noticing an empty list.
        if let storeLoadFailure = container.storeLoadFailure {
            lastErrorMessage = storeLoadFailure
        }
    }

    private func seedSampleDataIfRequested() async throws {
        #if DEBUG
        guard PrivionyxSampleData.isRequested, receipts.isEmpty else { return }

        for draft in PrivionyxSampleData.drafts() {
            try await container.saveReceiptUseCase.execute(draft)
        }
        try await loadReceipts()
        #endif
    }

    func initializeIfNeeded() async {
        guard hasCompletedInitialLoad == false, isLaunching == false else { return }
        isLaunching = true
        launchProgress = 0.08
        launchStatusText = "Loading saved receipts..."

        await bootstrapIfNeeded()
        launchProgress = 0.48

        launchStatusText = "Preparing app..."
        launchProgress = 1

        hasCompletedInitialLoad = true
        isLaunching = false
    }

    func refreshReceipts() async {
        do {
            try await loadReceipts()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func saveReceipt(_ draft: ReceiptDraft) async throws {
        try await container.saveReceiptUseCase.execute(draft)
        container.merchantRuleService.saveRule(merchant: draft.merchant, category: draft.category)
        try await loadReceipts()
    }

    func deleteReceipt(id: UUID) async throws {
        try await container.deleteReceiptUseCase.execute(id: id)
        try await loadReceipts()
    }

    private func loadReceipts() async throws {
        receipts = try await container.fetchReceiptsUseCase.execute()
        receiptsVersion += 1
    }
}

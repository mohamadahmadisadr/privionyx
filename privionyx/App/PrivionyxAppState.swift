import Observation
import CoreData
import Foundation

@MainActor
@Observable
final class PrivionyxAppState {
    let container: PrivionyxAppContainer
    /// What the user has bought, and the only authority on whether ads may show.
    let purchases: any PurchaseStore
    /// Where a banner comes from, if one comes from anywhere. `NoBannerAds` until an ad SDK
    /// and a unit id are both in place, at which point the app is exactly as it was before.
    let bannerAds: any BannerAdProviding
    private var hasCompletedInitialLoad = false
    /// Set once bootstrap has succeeded. Distinct from "there are no receipts": an empty
    /// library is a perfectly normal state, not a signal that the work still needs doing.
    private var hasBootstrapped = false

    private(set) var receipts: [ReceiptItem] = []
    private(set) var receiptsVersion = 0
    private(set) var isBootstrapping = false
    private(set) var isLaunching = false
    private(set) var launchProgress: Double = 0
    private(set) var launchStatusText = "Preparing app..."
    /// The most recent failure, in the form the user should see it. Cleared when the
    /// alert is dismissed.
    var lastError: UserFacingError?

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    /// AdMob when the SDK is linked, nothing at all when it isn't.
    static func defaultBannerAds() -> any BannerAdProviding {
        #if canImport(GoogleMobileAds)
        GoogleBannerAdProvider()
        #else
        NoBannerAds()
        #endif
    }

    init(
        container: PrivionyxAppContainer,
        purchases: any PurchaseStore = StoreKitPurchaseStore(),
        bannerAds: any BannerAdProviding = PrivionyxAppState.defaultBannerAds()
    ) {
        self.container = container
        self.purchases = purchases
        self.bannerAds = bannerAds
    }

    func bootstrapIfNeeded() async {
        guard hasBootstrapped == false, isBootstrapping == false else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        do {
            try await container.repository.performMaintenance()
            try await loadReceipts()
            try await seedSampleDataIfRequested()
            // Only on success, so a failed launch can still retry rather than being stuck
            // with whatever it managed to load.
            hasBootstrapped = true
        } catch {
            lastError = .loadingReceipts(error)
        }

        // Reported after loading rather than before, so it isn't overwritten by a load error
        // and so the user sees it against the receipts actually on screen. A reset store is
        // not something to discover by noticing an empty list.
        if let storeLoadFailure = container.storeLoadFailure {
            lastError = .storeUnavailable(storeLoadFailure)
        }
    }

    private func seedSampleDataIfRequested() async throws {
        guard PrivionyxSampleData.isRequested, receipts.isEmpty else { return }
        try await loadSampleReceipts()
    }

    // MARK: - Sample receipts

    /// Whether any sample receipt is currently in the library.
    ///
    /// Drives the removal affordance in Settings. It has to live there rather than only in the
    /// empty state, because loading samples is exactly what makes the empty state disappear —
    /// the one place the user could undo it would vanish with it.
    var hasSampleReceipts: Bool {
        receipts.contains { $0.tags.contains(PrivionyxSampleData.tag) }
    }

    /// Adds the example receipts. Never called except by a deliberate tap.
    func loadSampleReceipts() async throws {
        for draft in PrivionyxSampleData.drafts() {
            try await container.saveReceiptUseCase.execute(draft)
        }
        try await loadReceipts()
    }

    /// Removes every sample and nothing else.
    ///
    /// Selected by tag rather than by anything remembered from when they were added, so it
    /// stays correct across launches, across a restore from backup, and if the user has since
    /// edited one. A sample the user edited into something they want to keep is theirs to
    /// keep — untagging it in the editor is all that takes.
    func removeSampleReceipts() async throws {
        for receipt in receipts where receipt.tags.contains(PrivionyxSampleData.tag) {
            try await container.deleteReceiptUseCase.execute(id: receipt.id)
        }
        try await loadReceipts()
    }

    func initializeIfNeeded() async {
        guard hasCompletedInitialLoad == false, isLaunching == false else { return }
        isLaunching = true
        launchProgress = 0.08
        launchStatusText = "Loading saved receipts..."

        await bootstrapIfNeeded()
        launchProgress = 0.48

        // Reconciled during launch so an existing purchase is known before the first screen
        // draws — a paying user must never see a banner flash by on the way in.
        await purchases.refresh()

        launchStatusText = "Preparing app..."
        launchProgress = 1

        hasCompletedInitialLoad = true
        isLaunching = false
    }

    func refreshReceipts() async {
        do {
            try await loadReceipts()
        } catch {
            lastError = .loadingReceipts(error)
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

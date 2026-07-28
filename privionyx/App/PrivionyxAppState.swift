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
    /// Whether an ad may be requested at all, and whether the user was ever asked.
    let adConsent: any AdConsentProviding
    private var hasCompletedInitialLoad = false
    private var isInitializing = false
    /// Set once bootstrap has succeeded. Distinct from "there are no receipts": an empty
    /// library is a perfectly normal state, not a signal that the work still needs doing.
    private var hasBootstrapped = false

    private(set) var receipts: [ReceiptItem] = []
    private(set) var receiptsVersion = 0
    private(set) var isBootstrapping = false

    /// True until the first read of the library has finished, successfully or not.
    ///
    /// Screens draw placeholders while it holds rather than their empty state. An empty
    /// `receipts` array means two entirely different things — "you have saved nothing" and
    /// "nobody has looked yet" — and showing the first while the second is true tells the
    /// user their receipts are gone.
    private(set) var isLoadingLibrary = true

    /// The shortest time the placeholders stay up once the screen has drawn them.
    ///
    /// Not a delay for its own sake. A local library can come back in under a tenth of a
    /// second, and placeholders that appear and vanish within a few frames leave the user
    /// having seen nothing — which is the same as not telling them the app was working at
    /// all. Held for long enough to be read as what it is.
    private static let minimumPlaceholderDuration = Duration.milliseconds(400)

    /// True from process start until the first pass has settled.
    ///
    /// Its one job is holding banners back: `AdGate` refuses to show one while this is set,
    /// because until the entitlement has been reconciled the app does not yet know whether
    /// the user has paid to never see one.
    private(set) var isLaunching = true
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

    /// UMP when the SDK is linked, an unconditional yes when it isn't.
    static func defaultAdConsent() -> any AdConsentProviding {
        #if canImport(UserMessagingPlatform)
        GoogleAdConsentProvider()
        #else
        NoAdConsent()
        #endif
    }

    init(
        container: PrivionyxAppContainer,
        purchases: any PurchaseStore = StoreKitPurchaseStore(),
        bannerAds: any BannerAdProviding = PrivionyxAppState.defaultBannerAds(),
        adConsent: any AdConsentProviding = PrivionyxAppState.defaultAdConsent()
    ) {
        self.container = container
        self.purchases = purchases
        self.bannerAds = bannerAds
        self.adConsent = adConsent
    }

    /// An in-memory state already past its first load.
    ///
    /// Previews never call `initializeIfNeeded()`, so without this every one of them would sit
    /// under loading placeholders indefinitely instead of showing the content it was written
    /// to show.
    static var preview: PrivionyxAppState {
        let state = PrivionyxAppState(container: .preview)
        state.isLoadingLibrary = false
        return state
    }

    func bootstrapIfNeeded() async {
        guard hasBootstrapped == false, isBootstrapping == false else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        // The placeholders are already on screen — `isLoadingLibrary` starts true, so the very
        // first frame the app draws is the loading one. This is where they came up.
        let placeholdersShownAt = ContinuousClock.now

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

        let shown = ContinuousClock.now - placeholdersShownAt
        if shown < Self.minimumPlaceholderDuration {
            try? await Task.sleep(for: Self.minimumPlaceholderDuration - shown)
        }

        // Cleared whether the read succeeded or failed. A load that failed has still been
        // attempted, and leaving placeholders shimmering forever over an error the user has
        // already been shown would be worse than showing them the empty library.
        isLoadingLibrary = false
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

    /// Brings the app up. Nothing here gates the first screen — it is already on the glass by
    /// the time this runs, and each piece fills itself in as it arrives.
    func initializeIfNeeded() async {
        guard hasCompletedInitialLoad == false, isInitializing == false else { return }
        isInitializing = true
        defer { isInitializing = false }

        // Concurrently, because neither needs the other's answer: reading the library is Core
        // Data, and reconciling the entitlement is StoreKit's local transaction records. Run
        // in series, the faster of the two used to wait behind the slower for no reason.
        //
        // The entitlement only. Fetching the product is a network round trip to the App
        // Store, and nothing on screen at launch needs a price.
        //
        // Consent joins them for the same reason. It is a network round trip and, for a user
        // in a regulated region, a form they have to dismiss — neither of which the receipt
        // list has any business waiting behind. `isLoadingLibrary` is cleared by
        // `bootstrapIfNeeded` itself, so the app is fully usable underneath the form.
        async let library: Void = bootstrapIfNeeded()
        async let entitlement: Void = reconcileEntitlement()
        async let consent: Void = resolveAdConsent()
        _ = await (library, entitlement, consent)

        hasCompletedInitialLoad = true
        isLaunching = false
    }

    /// Asks the user what the ad SDK may do, then starts it if the answer allows.
    ///
    /// Launch waits for this before showing a banner — not because the screen needs it, but
    /// because `AdGate` reads `canRequestAds` and the honest value before this returns is
    /// "not yet". A method rather than the call written inline above for the same reason as
    /// `reconcileEntitlement()`: `any AdConsentProviding` is not `Sendable`.
    private func resolveAdConsent() async {
        await adConsent.requestConsentUpdate()
        guard adConsent.canRequestAds else { return }
        bannerAds.startRequestingAds()
    }

    /// `purchases.refreshEntitlement()`, reachable from a child task.
    ///
    /// A method rather than the call written inline above because `any PurchaseStore` is not
    /// `Sendable`, so reading the property to start the task is not allowed to leave the main
    /// actor — where going through `self`, which is `@MainActor` and therefore is, is.
    private func reconcileEntitlement() async {
        await purchases.refreshEntitlement()
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

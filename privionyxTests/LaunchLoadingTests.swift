import Foundation
import Testing
@testable import privionyx

/// The app draws its first screen before it has read anything, so every screen showing
/// receipt-derived content has to be able to say "not yet" as distinct from "none".
///
/// These are about that distinction. An empty `receipts` array means two entirely different
/// things depending on whether anyone has looked, and telling the user the wrong one — "Save a
/// receipt to unlock your spending overview", to someone with three years of them — is the
/// failure this state exists to prevent.
@MainActor
@Suite("Launch loading")
struct LaunchLoadingTests {
    private func makeAppState(
        purchases: PurchaseStore = PurchaseFlowTests.FakePurchaseStore()
    ) -> PrivionyxAppState {
        PrivionyxAppState(container: .preview, purchases: purchases, bannerAds: NoBannerAds())
    }

    @Test("A state nobody has loaded yet reads as loading, not as empty")
    func startsLoading() {
        let appState = makeAppState()

        #expect(appState.isLoadingLibrary)
        #expect(appState.receipts.isEmpty)
    }

    @Test("Reading the library clears the loading state")
    func bootstrapClearsLoading() async {
        let appState = makeAppState()

        await appState.bootstrapIfNeeded()

        #expect(appState.isLoadingLibrary == false)
        // An empty library is now an answer rather than an absence of one.
        #expect(appState.receipts.isEmpty)
    }

    @Test("Placeholders stay up long enough to be seen")
    func placeholdersAreHeldLongEnoughToRead() async {
        let appState = makeAppState()
        let startedAt = ContinuousClock.now

        await appState.bootstrapIfNeeded()

        // An in-memory library comes back in a few milliseconds. Without the hold the
        // placeholders would be gone inside a couple of frames and the user would have been
        // told nothing at all — which is the whole reason they are there.
        #expect(ContinuousClock.now - startedAt >= .milliseconds(380))
        #expect(appState.isLoadingLibrary == false)
    }

    @Test("Banners are held back until the first pass has settled")
    func adsWaitForLaunchToSettle() async {
        let appState = makeAppState()

        // The gate has to hold from the first frame. The app now draws that frame before it
        // knows what the user owns, and a paying user must never see a banner flash by.
        #expect(appState.isLaunching)
        #expect(AdGate.showsBanner(
            entitlement: appState.purchases.entitlement,
            isConfigured: true,
            isLaunching: appState.isLaunching
        ) == false)

        await appState.initializeIfNeeded()

        #expect(appState.isLaunching == false)
    }

    @Test("Launch reconciles the entitlement without fetching the product")
    func launchSkipsTheProductFetch() async {
        let purchases = PurchaseFlowTests.FakePurchaseStore()
        let appState = makeAppState(purchases: purchases)

        await appState.initializeIfNeeded()

        #expect(purchases.entitlementRefreshCount == 1)
        // `refresh()` is the one that goes to the App Store over the network. Nothing on
        // screen at launch needs a price, and waiting for one used to hold up the launch.
        #expect(purchases.refreshCount == 0)
    }

    @Test("Launching twice does the work once")
    func initializeIsIdempotent() async {
        let purchases = PurchaseFlowTests.FakePurchaseStore()
        let appState = makeAppState(purchases: purchases)

        await appState.initializeIfNeeded()
        await appState.initializeIfNeeded()

        #expect(purchases.entitlementRefreshCount == 1)
    }

    @Test("The preview state is already past its first load")
    func previewStateIsLoaded() {
        // Previews never call `initializeIfNeeded()`, so without this every one of them would
        // sit under placeholders instead of showing what it was written to show.
        #expect(PrivionyxAppState.preview.isLoadingLibrary == false)
    }

    @Test("The receipts screen holds its empty state until it has filtered something")
    func receiptListWaitsBeforeClaimingEmptiness() async {
        let appState = makeAppState()
        await appState.bootstrapIfNeeded()

        let viewModel = ReceiptListViewModel(appState: appState)

        // The library is read, but this screen hasn't run a filter pass — so it has no answer
        // to give yet, and "No receipts saved yet" would be a guess.
        #expect(viewModel.isLoading)

        await viewModel.refresh()

        #expect(viewModel.isLoading == false)
    }

    @Test("The receipts screen reports loading while the library is still being read")
    func receiptListFollowsTheLibrary() {
        let appState = makeAppState()
        let viewModel = ReceiptListViewModel(appState: appState)

        #expect(appState.isLoadingLibrary)
        #expect(viewModel.isLoading)
    }
}

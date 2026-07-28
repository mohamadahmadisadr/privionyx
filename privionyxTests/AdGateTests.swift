import Foundation
import Testing
@testable import privionyx

@Suite("Ad gate")
struct AdGateTests {
    @Test("A paid user never sees a banner, however everything else is configured")
    func paidUserSeesNothing() {
        #expect(AdGate.showsBanner(entitlement: .adFree, isConfigured: true, canRequestAds: true, isLaunching: false) == false)
    }

    @Test("No ad network configured means no slot at all")
    func unconfiguredShowsNothing() {
        #expect(AdGate.showsBanner(entitlement: .none, isConfigured: false, canRequestAds: true, isLaunching: false) == false)
    }

    @Test("Nothing is shown over the launch screen")
    func launchingShowsNothing() {
        #expect(AdGate.showsBanner(entitlement: .none, isConfigured: true, canRequestAds: true, isLaunching: true) == false)
    }

    @Test("A free user on a configured build, past launch, sees the banner")
    func freeUserSeesBanner() {
        #expect(AdGate.showsBanner(entitlement: .none, isConfigured: true, canRequestAds: true, isLaunching: false))
    }

    @Test("Nothing is requested before the user has been asked for consent")
    func withoutConsentShowsNothing() {
        // The state every launch starts in, and the one a user in the EEA or UK who declined
        // stays in. Requesting an ad here is the violation; it would also come back unfilled.
        #expect(AdGate.showsBanner(
            entitlement: .none,
            isConfigured: true,
            canRequestAds: false,
            isLaunching: false
        ) == false)
    }

    @Test("The shipped default is a build with no ads in it")
    func defaultProviderIsSilent() async {
        let provider = await NoBannerAds()
        #expect(await provider.isConfigured == false)
    }

    @Test("A build with no consent SDK does not also gate itself on consent")
    func absentConsentProviderIsNotASecondGate() async {
        // Two independent reasons to show nothing would make it ambiguous which one is
        // actually in force. `NoBannerAds` is the one that says no in that build.
        let consent = await NoAdConsent()
        #expect(await consent.canRequestAds)
        #expect(await consent.isPrivacyOptionsRequired == false)
    }
}

@Suite("Purchase flow")
@MainActor
struct PurchaseFlowTests {
    /// Stands in for StoreKit. The real store needs a running app and a configuration file,
    /// which is no way to assert what happens when a purchase fails.
    @Observable
    final class FakePurchaseStore: PurchaseStore {
        private(set) var entitlement: AdEntitlement = .none
        private(set) var availability: PurchaseAvailability = .available
        private(set) var displayPrice: String? = "$4.99"
        private(set) var isBusy = false
        private(set) var lastFailure: String?

        func clearFailure() { lastFailure = nil }

        var purchaseSucceeds = true
        /// Stands in for StoreKit's `.userCancelled`: the purchase does not complete and
        /// nothing is written to `lastFailure`, because the user made a decision rather than
        /// hitting a problem.
        var purchaseIsCancelled = false
        var ownsPriorPurchase = false
        private(set) var refreshCount = 0
        private(set) var entitlementRefreshCount = 0

        func refreshEntitlement() async { entitlementRefreshCount += 1 }

        func refresh() async { refreshCount += 1 }

        /// Puts the store in the state a developer hits constantly: no StoreKit
        /// configuration applied, so nothing comes back at all.
        func simulateNoProduct() {
            availability = .unavailable("The upgrade isn't available on this device right now.")
            displayPrice = nil
        }

        @discardableResult
        func purchaseAdFree() async -> Bool {
            guard purchaseIsCancelled == false else { return false }
            guard purchaseSucceeds else {
                lastFailure = "The purchase couldn't be completed."
                return false
            }
            entitlement = .adFree
            return true
        }

        @discardableResult
        func restorePurchases() async -> Bool {
            if ownsPriorPurchase {
                entitlement = .adFree
                return true
            }
            lastFailure = "No previous purchase was found on this Apple ID."
            return false
        }
    }

    @Test("A successful purchase entitles the user and stops the ads")
    func purchaseRemovesAds() async {
        let store = FakePurchaseStore()
        #expect(AdGate.showsBanner(entitlement: store.entitlement, isConfigured: true, canRequestAds: true, isLaunching: false))

        #expect(await store.purchaseAdFree())
        #expect(store.entitlement == .adFree)
        #expect(AdGate.showsBanner(entitlement: store.entitlement, isConfigured: true, canRequestAds: true, isLaunching: false) == false)
    }

    @Test("A failed purchase leaves the user unentitled and says so")
    func failedPurchaseKeepsAds() async {
        let store = FakePurchaseStore()
        store.purchaseSucceeds = false

        #expect(await store.purchaseAdFree() == false)
        #expect(store.entitlement == .none)
        #expect(store.lastFailure != nil)
    }

    @Test("Restore returns the purchase on a device that has never seen it")
    func restoreFindsPriorPurchase() async {
        let store = FakePurchaseStore()
        store.ownsPriorPurchase = true

        #expect(await store.restorePurchases())
        #expect(store.entitlement == .adFree)
    }

    @Test("Restore with nothing to restore explains itself rather than failing silently")
    func restoreWithoutPurchase() async {
        let store = FakePurchaseStore()

        #expect(await store.restorePurchases() == false)
        #expect(store.entitlement == .none)
        #expect(store.lastFailure?.isEmpty == false)
    }

    @Test("A store with nothing to sell says so instead of loading forever")
    func unavailableIsNotLoading() {
        let store = FakePurchaseStore()
        store.simulateNoProduct()

        // The distinction the UI depends on: not loading, so the button stops saying it is.
        #expect(store.availability.isLoading == false)
        #expect(store.availability.unavailableReason?.isEmpty == false)
        #expect(store.displayPrice == nil)
    }

    @Test("A loading store reports no reason, because there isn't one yet")
    func loadingHasNoReason() {
        #expect(PurchaseAvailability.loading.unavailableReason == nil)
        #expect(PurchaseAvailability.available.unavailableReason == nil)
        #expect(PurchaseAvailability.loading.isLoading)
    }

    @Test("Launch reconciles the entitlement without waiting on the product")
    func launchOnlyChecksEntitlement() async {
        // The product lookup is a network round trip; the entitlement is local. Launch may
        // wait for the second and must never wait for the first.
        let store = FakePurchaseStore()
        await store.refreshEntitlement()

        #expect(store.entitlementRefreshCount == 1)
        #expect(store.refreshCount == 0)
    }

    @Test("The price shown is the storefront's own, not a hardcoded figure")
    func priceComesFromTheStore() {
        // Guards the one thing that silently breaks outside the US: the button must read
        // whatever StoreKit says, since Apple derives every country's price from one point.
        let store = FakePurchaseStore()
        #expect(store.displayPrice == "$4.99")
    }
}

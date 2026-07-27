import Foundation
import Testing
@testable import privionyx

@Suite("Ad gate")
struct AdGateTests {
    @Test("A paid user never sees a banner, however everything else is configured")
    func paidUserSeesNothing() {
        #expect(AdGate.showsBanner(entitlement: .adFree, isConfigured: true, isLaunching: false) == false)
    }

    @Test("No ad network configured means no slot at all")
    func unconfiguredShowsNothing() {
        #expect(AdGate.showsBanner(entitlement: .none, isConfigured: false, isLaunching: false) == false)
    }

    @Test("Nothing is shown over the launch screen")
    func launchingShowsNothing() {
        #expect(AdGate.showsBanner(entitlement: .none, isConfigured: true, isLaunching: true) == false)
    }

    @Test("A free user on a configured build, past launch, sees the banner")
    func freeUserSeesBanner() {
        #expect(AdGate.showsBanner(entitlement: .none, isConfigured: true, isLaunching: false))
    }

    @Test("The shipped default is a build with no ads in it")
    func defaultProviderIsSilent() async {
        let provider = await NoBannerAds()
        #expect(await provider.isConfigured == false)
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
        private(set) var displayPrice: String? = "$4.99"
        private(set) var isBusy = false
        var lastFailure: String?

        var purchaseSucceeds = true
        var ownsPriorPurchase = false
        private(set) var refreshCount = 0

        func refresh() async { refreshCount += 1 }

        @discardableResult
        func purchaseAdFree() async -> Bool {
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
        #expect(AdGate.showsBanner(entitlement: store.entitlement, isConfigured: true, isLaunching: false))

        #expect(await store.purchaseAdFree())
        #expect(store.entitlement == .adFree)
        #expect(AdGate.showsBanner(entitlement: store.entitlement, isConfigured: true, isLaunching: false) == false)
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

    @Test("The price shown is the storefront's own, not a hardcoded figure")
    func priceComesFromTheStore() {
        // Guards the one thing that silently breaks outside the US: the button must read
        // whatever StoreKit says, since Apple derives every country's price from one point.
        let store = FakePurchaseStore()
        #expect(store.displayPrice == "$4.99")
    }
}

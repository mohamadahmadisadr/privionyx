import Foundation
import Observation
import StoreKit

/// The real store, on StoreKit 2.
///
/// No receipt validation server and no server-side entitlement: `Transaction.currentEntitlements`
/// is already verified by the OS, and for a single non-consumable there is nothing a backend
/// could add except somewhere else for the answer to be wrong.
@MainActor
@Observable
final class StoreKitPurchaseStore: PurchaseStore {
    private(set) var entitlement: AdEntitlement = .none
    private(set) var displayPrice: String?
    private(set) var isBusy = false
    var lastFailure: String?

    @ObservationIgnored private var product: Product?
    /// Watches for transactions that happen outside a purchase call — a family member's
    /// share, an Ask to Buy approval, a purchase made on another device. Without it the app
    /// would keep showing ads to someone who already paid until they next relaunched.
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await self.apply(update)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refresh() async {
        await loadProduct()
        await refreshEntitlement()
    }

    @discardableResult
    func purchaseAdFree() async -> Bool {
        guard isBusy == false else { return entitlement.removesAds }
        isBusy = true
        defer { isBusy = false }

        // The product may not have loaded yet — a first tap on a cold, slow network gets one
        // more attempt rather than a shrug.
        if product == nil { await loadProduct() }

        guard let product else {
            lastFailure = "The store is unavailable right now. Please try again in a moment."
            return false
        }

        do {
            switch try await product.purchase() {
            case let .success(verification):
                await apply(verification)
                return entitlement.removesAds

            case .userCancelled:
                // Not a failure. The user changed their mind; saying anything would be nagging.
                return false

            case .pending:
                // Ask to Buy, or a payment method needing action. The transaction will arrive
                // through `Transaction.updates` if and when it is approved.
                lastFailure = "Your purchase is pending approval. Ads will be removed as soon as it goes through."
                return false

            @unknown default:
                return false
            }
        } catch {
            lastFailure = "The purchase couldn't be completed. \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        guard isBusy == false else { return entitlement.removesAds }
        isBusy = true
        defer { isBusy = false }

        do {
            // Asks the App Store to re-deliver, which is what makes a restore work after a
            // reinstall on a device whose local records are empty.
            try await AppStore.sync()
        } catch {
            // A cancelled sign-in throws here too, so this is reported but not fatal: the
            // entitlement check below is still worth running.
            lastFailure = "Couldn't reach the App Store to restore. \(error.localizedDescription)"
        }

        await refreshEntitlement()

        if entitlement.removesAds == false, lastFailure == nil {
            lastFailure = "No previous purchase was found on this Apple ID."
        }
        return entitlement.removesAds
    }

    // MARK: - StoreKit

    private func loadProduct() async {
        do {
            product = try await Product.products(for: [PrivionyxProduct.removeAds]).first
            displayPrice = product?.displayPrice

            if product == nil {
                // Almost always a configuration problem rather than a runtime one: the
                // product is missing, not approved, or the Paid Applications Agreement is
                // unsigned. Left silent for the user; the button simply stays unavailable.
                lastFailure = nil
            }
        } catch {
            lastFailure = "Couldn't load the upgrade. \(error.localizedDescription)"
        }
    }

    private func refreshEntitlement() async {
        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            if transaction.productID == PrivionyxProduct.removeAds, transaction.revocationDate == nil {
                entitlement = .adFree
                return
            }
        }
        entitlement = .none
    }

    /// Accepts a transaction only if the OS vouches for its signature, then finishes it.
    ///
    /// An unverified transaction is ignored rather than trusted-and-logged: the only thing it
    /// could buy is the removal of ads, and treating a forged one as valid is the whole of
    /// the harm this check exists to prevent.
    private func apply(_ result: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = result else { return }

        if transaction.productID == PrivionyxProduct.removeAds, transaction.revocationDate == nil {
            entitlement = .adFree
        }

        // Unfinished transactions are re-delivered on every launch forever.
        await transaction.finish()
    }
}

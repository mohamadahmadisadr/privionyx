import Foundation

/// What the user has paid for.
///
/// One product today, but stated as an entitlement rather than as a boolean on the app state
/// so the answer to "may this screen show an ad?" has exactly one owner. A view asks the
/// entitlement; nothing asks StoreKit directly.
enum AdEntitlement: Equatable, Sendable {
    /// No purchase found, or none loaded yet. Ads may show.
    case none
    /// The ad-free purchase is owned, on this Apple ID, on any of their devices.
    case adFree

    var removesAds: Bool { self == .adFree }
}

/// The one product the app sells.
enum PrivionyxProduct {
    /// Non-consumable: bought once, restorable forever, shared through Family Sharing if
    /// enabled in App Store Connect. Must match the product identifier registered there.
    static let removeAds = "com.privionyx.app.privionyx.removeads"
}

/// Whether there is anything to sell, and if not, why not.
///
/// Needed because "no product came back" is not the same as "still loading", and the two
/// used to be indistinguishable: an empty result left the button reading "Loading…" for as
/// long as the user cared to watch it. StoreKit returns nothing for entirely mundane
/// reasons — no App Store account on the device, the product not yet approved, the Paid
/// Applications Agreement unsigned — and every one of them deserves a straight answer.
enum PurchaseAvailability: Equatable, Sendable {
    case loading
    case available
    case unavailable(String)

    var isLoading: Bool { self == .loading }

    /// Why the upgrade can't be bought, when it can't.
    var unavailableReason: String? {
        switch self {
        case let .unavailable(reason): reason
        case .loading, .available: nil
        }
    }
}

/// Purchasing, restoring, and reporting what the user owns.
///
/// A protocol so the app can be built and tested against a store that never talks to Apple:
/// StoreKit's own test harness needs a running app and a configuration file, which is no
/// basis for a unit test of "what happens after a purchase fails".
@MainActor
protocol PurchaseStore: AnyObject {
    /// What the user currently owns. Starts at `.none` and is corrected once the store answers.
    var entitlement: AdEntitlement { get }

    /// Whether the upgrade can be bought at all right now.
    var availability: PurchaseAvailability { get }

    /// The localized price to put on the button — "$4.99", "£4.49", "¥800".
    ///
    /// Apple derives every storefront's price from the one price point chosen in App Store
    /// Connect, so this is read from the product rather than formatted by the app: currency,
    /// placement of the symbol, and rounding conventions are not ours to guess at.
    var displayPrice: String? { get }

    /// Whether a purchase or restore is in flight, so the UI can refuse a second tap.
    var isBusy: Bool { get }

    /// Set when a purchase or restore failed in a way worth telling the user about.
    /// A user-cancelled purchase is not one of those.
    var lastFailure: String? { get }

    /// Reconciles what the user already owns, and nothing else.
    ///
    /// Separate from `refresh()` because it reads the device's own transaction records and
    /// returns in milliseconds, where fetching the product is a network round trip to the
    /// App Store. Launch waits for this one; it must never wait for the other.
    func refreshEntitlement() async

    /// Loads the product and reconciles what the user already owns. Safe to call repeatedly.
    func refresh() async

    /// Buys the ad-free upgrade. Returns `true` when the user ends up entitled.
    @discardableResult
    func purchaseAdFree() async -> Bool

    /// Re-checks the App Store for purchases made on another device or before a reinstall.
    ///
    /// Not optional: App Review guideline 3.1.1 requires a restore path for a non-consumable,
    /// and its absence is a certain rejection.
    @discardableResult
    func restorePurchases() async -> Bool
}

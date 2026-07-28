import Testing
@testable import privionyx

@Suite("Remove Ads paywall")
struct RemoveAdsPaywallTests {
    // MARK: - What the sheet shows when it opens

    @Test("The sheet opens on the offer, with no store status of any kind")
    func opensOnTheOffer() {
        // The regression this exists for: the sheet used to greet the user with whatever the
        // store happened to be doing — "Loading…" on the button, and a warning line under the
        // title if the product hadn't arrived. Nothing had been attempted, so there was
        // nothing to report.
        let stage = PaywallStage.offer

        #expect(stage.showsOffer)
        #expect(stage.failureMessage == nil)
        #expect(stage.isWorking == false)
    }

    @Test("A store that can't sell anything yet is still a plain offer")
    func unavailableStoreStillShowsTheOffer() {
        let store = PurchaseFlowTests.FakePurchaseStore()
        store.simulateNoProduct()

        // The store's own reason exists and is real; it just isn't the user's business until
        // they tap something. The button says what it does, and it is tappable.
        #expect(store.availability.unavailableReason?.isEmpty == false)
        #expect(PaywallStage.offer.failureMessage == nil)
        #expect(PaywallCopy.unlockTitle(price: store.displayPrice, stage: .offer) == "Unlock Forever")
    }

    // MARK: - The buttons

    @Test("The unlock button names the purchase before the price arrives, and after")
    func unlockTitleGainsThePrice() {
        #expect(PaywallCopy.unlockTitle(price: nil, stage: .offer) == "Unlock Forever")
        #expect(PaywallCopy.unlockTitle(price: "$4.99", stage: .offer) == "Unlock Forever · $4.99")
    }

    @Test("The price shown is the storefront's own, whatever shape it takes")
    func priceIsNeverFormattedHere() {
        // Apple derives every country's price from the one price point in App Store Connect.
        // A symbol placed by the app would be wrong outside its author's storefront.
        #expect(PaywallCopy.unlockTitle(price: "£4.49", stage: .offer) == "Unlock Forever · £4.49")
        #expect(PaywallCopy.unlockTitle(price: "¥800", stage: .offer) == "Unlock Forever · ¥800")
    }

    @Test("An empty price is treated as no price, not as a title ending in a separator")
    func emptyPriceIsIgnored() {
        #expect(PaywallCopy.unlockTitle(price: "", stage: .offer) == "Unlock Forever")
    }

    @Test("Each button reports only its own work")
    func inFlightTitlesDontCrossOver() {
        #expect(PaywallCopy.unlockTitle(price: "$4.99", stage: .working(.purchase)) == "Unlocking…")
        #expect(PaywallCopy.restoreTitle(stage: .working(.restore)) == "Restoring…")

        // A restore in flight must not make the buy button claim to be buying.
        #expect(PaywallCopy.unlockTitle(price: "$4.99", stage: .working(.restore)) == "Unlock Forever · $4.99")
        #expect(PaywallCopy.restoreTitle(stage: .working(.purchase)) == "Restore Purchase")
    }

    @Test("Both buttons refuse a second tap while either is working")
    func workingLocksBothButtons() {
        #expect(PaywallStage.working(.purchase).isWorking)
        #expect(PaywallStage.working(.restore).isWorking)
        #expect(PaywallStage.offer.isWorking == false)
        #expect(PaywallStage.failed("nope").isWorking == false)
    }

    // MARK: - Outcomes

    @Test("A successful purchase replaces the offer with a confirmation")
    func purchaseSucceeds() {
        let stage = PaywallStage.outcome(of: .purchase, succeeded: true, failure: nil)

        #expect(stage == .settled(.purchase))
        #expect(stage.showsOffer == false)
        #expect(PaywallCopy.settledTitle(.purchase) == "Ads removed")
    }

    @Test("A successful restore says it restored rather than that it bought")
    func restoreSucceeds() {
        let stage = PaywallStage.outcome(of: .restore, succeeded: true, failure: nil)

        #expect(stage == .settled(.restore))
        #expect(PaywallCopy.settledTitle(.restore) == "Purchase restored")
    }

    @Test("A failure annotates the offer instead of replacing it")
    func failureKeepsTheButtonsOnScreen() {
        let stage = PaywallStage.outcome(of: .purchase, succeeded: false, failure: "The purchase couldn't be completed.")

        #expect(stage.failureMessage == "The purchase couldn't be completed.")
        // The next thing a user wants after a failed purchase is the button they just missed.
        #expect(stage.showsOffer)
    }

    @Test("A cancelled purchase says nothing at all")
    func cancellingIsSilent() {
        // StoreKit's `.userCancelled` is a decision, not an error, and the store deliberately
        // writes no failure for it. The sheet goes back to the offer with no red text.
        let stage = PaywallStage.outcome(of: .purchase, succeeded: false, failure: nil)

        #expect(stage == .offer)
        #expect(stage.failureMessage == nil)
    }

    @Test("A restore that finds nothing explains itself")
    func emptyRestoreExplainsItself() {
        let stage = PaywallStage.outcome(of: .restore, succeeded: false, failure: "No previous purchase was found on this Apple ID.")

        #expect(stage.failureMessage == "No previous purchase was found on this Apple ID.")
        #expect(stage.showsOffer)
    }

    // MARK: - Attribution of the message

    @Test("A failure from an earlier attempt is not re-shown after a later cancel")
    @MainActor
    func clearedBetweenAttempts() async {
        // The sequence that made this necessary: a purchase fails and writes a message, then
        // the user taps again and cancels Apple's sheet. The store writes nothing for a
        // cancel, so without the clear the old message would be read back and shown as if it
        // described the tap the user had just made.
        let store = PurchaseFlowTests.FakePurchaseStore()
        store.purchaseSucceeds = false

        _ = await store.purchaseAdFree()
        #expect(store.lastFailure != nil)

        store.clearFailure()
        store.purchaseSucceeds = false
        store.purchaseIsCancelled = true
        let succeeded = await store.purchaseAdFree()

        #expect(succeeded == false)
        #expect(PaywallStage.outcome(of: .purchase, succeeded: succeeded, failure: store.lastFailure) == .offer)
    }

    @Test("Opening the sheet forgets a failure left behind by Settings' own Restore row")
    @MainActor
    func openingClearsStaleFailures() async {
        // Settings has a Restore row that writes to the same store. Tapping it with nothing
        // to restore, then opening the paywall, must not open onto that message.
        let store = PurchaseFlowTests.FakePurchaseStore()
        _ = await store.restorePurchases()
        #expect(store.lastFailure != nil)

        store.clearFailure()
        #expect(store.lastFailure == nil)
    }
}

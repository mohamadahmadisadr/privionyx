import Foundation
import Testing
@testable import privionyx

@Suite("Totals reconciliation")
struct ReceiptTotalsReconcilerTests {
    private let reconciler = ReceiptTotalsReconciler()

    @Test("Balanced figures are left alone")
    func balancedFiguresUntouched() {
        let result = reconciler.reconcile(total: 4.61, subtotal: 4.08, tax: 0.53, tip: nil)

        #expect(result.status == .consistent)
        #expect(result.total == 4.61)
        #expect(result.subtotal == 4.08)
        #expect(result.tax == 0.53)
    }

    @Test("A tip is included in the identity")
    func tipCountsTowardTotal() {
        let result = reconciler.reconcile(total: 63.84, subtotal: 48.00, tax: 6.24, tip: 9.60)

        #expect(result.status == .consistent)
    }

    /// The crumpled-receipt case: the TOTAL row never reached OCR, so extraction fell back
    /// to the subtotal. A receipt charging tax cannot have total == subtotal.
    @Test("A total equal to the subtotal is repaired when tax is charged")
    func totalMistakenForSubtotalIsRepaired() {
        let result = reconciler.reconcile(total: 327.75, subtotal: 327.75, tax: 15.20, tip: nil)

        #expect(result.status == .repaired)
        #expect(result.total == 342.95)
        #expect(result.subtotal == 327.75)
    }

    /// A tax-free receipt legitimately has total == subtotal, so it must not be "repaired".
    @Test("A zero-tax receipt with total equal to subtotal stays consistent")
    func zeroTaxReceiptNotRepaired() {
        let result = reconciler.reconcile(total: 31.45, subtotal: 31.45, tax: 0.00, tip: nil)

        #expect(result.status == .consistent)
        #expect(result.total == 31.45)
    }

    @Test("A missing total is derived from its parts")
    func missingTotalDerived() {
        let result = reconciler.reconcile(total: nil, subtotal: 20.00, tax: 2.60, tip: nil)

        #expect(result.status == .repaired)
        #expect(result.total == 22.60)
    }

    @Test("A missing subtotal is derived from total and tax")
    func missingSubtotalDerived() {
        let result = reconciler.reconcile(total: 22.60, subtotal: nil, tax: 2.60, tip: nil)

        #expect(result.status == .repaired)
        #expect(result.subtotal == 20.00)
    }

    @Test("A missing tax is derived from total and subtotal")
    func missingTaxDerived() {
        let result = reconciler.reconcile(total: 22.60, subtotal: 20.00, tax: nil, tip: nil)

        #expect(result.status == .repaired)
        #expect(result.tax == 2.60)
    }

    /// A lone total says nothing about how it splits. Deriving a subtotal here would be
    /// invention, and a spurious value is worse than an absent one.
    @Test("A lone total invents nothing")
    func loneTotalStaysAlone() {
        let result = reconciler.reconcile(total: 52.00, subtotal: nil, tax: nil, tip: nil)

        #expect(result.status == .unverified)
        #expect(result.total == 52.00)
        #expect(result.subtotal == nil)
        #expect(result.tax == nil)
    }

    @Test("Figures that cannot be explained by one repair are flagged, not rewritten")
    func unexplainableFiguresFlagged() {
        // 10 + 1 is nowhere near 99, and the total does not match the subtotal either.
        let result = reconciler.reconcile(total: 99.00, subtotal: 10.00, tax: 1.00, tip: nil)

        #expect(result.status == .inconsistent)
        #expect(result.total == 99.00)
        #expect(result.subtotal == 10.00)
        #expect(result.tax == 1.00)
    }

    @Test("Only computed figures are reported as derived")
    func derivedFieldsAreReported() {
        #expect(reconciler.reconcile(total: 327.75, subtotal: 327.75, tax: 15.20, tip: nil)
            .derived == [.total])
        #expect(reconciler.reconcile(total: 22.60, subtotal: nil, tax: 2.60, tip: nil)
            .derived == [.subtotal])
        #expect(reconciler.reconcile(total: 22.60, subtotal: 20.00, tax: nil, tip: nil)
            .derived == [.tax])
    }

    @Test("Figures read straight off the receipt are never reported as derived")
    func readFiguresAreNotDerived() {
        #expect(reconciler.reconcile(total: 4.61, subtotal: 4.08, tax: 0.53, tip: nil)
            .derived.isEmpty)
        #expect(reconciler.reconcile(total: 52.00, subtotal: nil, tax: nil, tip: nil)
            .derived.isEmpty)
        #expect(reconciler.reconcile(total: 99.00, subtotal: 10.00, tax: 1.00, tip: nil)
            .derived.isEmpty)
    }

    /// Restaurants print a mandatory service charge both ways: above the subtotal on some
    /// receipts, folded into it on others. The label is identical; only the arithmetic tells
    /// them apart.
    @Test("A tip already inside the subtotal is dropped rather than counted twice")
    func tipAlreadyInSubtotalIsDropped() {
        let result = reconciler.reconcile(total: 229.94, subtotal: 211.68, tax: 18.26, tip: 33.60)

        #expect(result.status == .repaired)
        #expect(result.tip == nil)
        #expect(result.total == 229.94)
        #expect(result.subtotal == 211.68)
    }

    @Test("A tip genuinely outside the subtotal is kept")
    func tipOutsideSubtotalIsKept() {
        let result = reconciler.reconcile(total: 71.11, subtotal: 56.00, tax: 5.03, tip: 10.08)

        #expect(result.status == .consistent)
        #expect(result.tip == 10.08)
    }

    /// Generalises the crumpled-receipt repair: equality was only the special case. Here a
    /// tax line outranked a total whose label the token lists do not recognise.
    @Test("A total below the subtotal is repaired, not just one equal to it")
    func totalBelowSubtotalIsRepaired() {
        let result = reconciler.reconcile(total: 0.77, subtotal: 33.80, tax: 0.77, tip: nil)

        #expect(result.status == .repaired)
        #expect(result.total == 34.57)
        #expect(result.derived == [.total])
    }

    @Test("Cent-level rounding still counts as balanced")
    func centRoundingTolerated() {
        let result = reconciler.reconcile(total: 18.14, subtotal: 15.78, tax: 2.36, tip: nil)

        #expect(result.status == .consistent)
    }
}

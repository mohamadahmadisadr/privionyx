import Foundation

/// Checks the totals block against the identity `subtotal + tax + tip = total`, filling in
/// what recognition could not read and flagging what does not add up.
///
/// This is the one cross-check a receipt supplies about itself, and it is what lets the
/// pipeline recover a value that is physically illegible — a creased photograph whose TOTAL
/// row never reaches OCR still yields its total, because the subtotal and tax did.
///
/// The reconciler only ever *fills in* or repairs a value it can prove wrong. It does not
/// overwrite a figure that balances, because a confidently-read total is better evidence
/// than a sum of two figures that may each be misread.
struct ReceiptTotalsReconciler {
    /// Receipts are written to the cent. The slack is for binary floating point, not for
    /// tolerating genuine disagreement.
    static let tolerance = 0.011

    enum Status: Equatable, Hashable, Sendable {
        /// The figures balance.
        case consistent
        /// A missing or provably wrong figure was derived from the others.
        case repaired
        /// Too few figures to check anything against.
        case unverified
        /// The figures are present and do not balance, and no single repair explains it.
        case inconsistent
    }

    /// A figure in the totals block that reconciliation is able to derive.
    enum Field: String, CaseIterable, Hashable, Sendable {
        case total
        case subtotal
        case tax
    }

    struct Result: Equatable {
        var total: Double?
        var subtotal: Double?
        var tax: Double?
        var tip: Double?
        var status: Status
        /// Figures computed from the others rather than read off the receipt. These are
        /// the ones worth putting in front of the user, because arithmetic can only be as
        /// right as the figures it was given.
        var derived: Set<Field> = []
    }

    func reconcile(total: Double?, subtotal: Double?, tax: Double?, tip: Double?) -> Result {
        var result = Result(total: total, subtotal: subtotal, tax: tax, tip: tip, status: .unverified)
        let tipValue = tip ?? 0

        switch (total, subtotal, tax) {
        case let (total?, subtotal?, tax?):
            if Self.balances(total: total, subtotal: subtotal, tax: tax, tip: tipValue) {
                result.status = .consistent
            } else if tipValue > Self.tolerance,
                      Self.balances(total: total, subtotal: subtotal, tax: tax, tip: 0) {
                // The figures balance only once the tip is left out, so it was already inside
                // the subtotal. Restaurants print a mandatory service charge both ways — above
                // the subtotal on some, folded into it on others — and the label reads the same
                // either way. Only the arithmetic distinguishes them, and counting it twice
                // would overstate the tip and leave the receipt not adding up.
                result.tip = nil
                result.status = .repaired
            } else if Self.totalCannotBeTheTotal(total: total, subtotal: subtotal, tax: tax, tip: tipValue) {
                // Whatever was read as the total is at or below the subtotal, so it is not the
                // total: either the row never reached OCR and the subtotal stood in for it, or
                // a smaller figure beside it won. The sum is the better answer either way.
                result.total = Self.roundedToCents(subtotal + tax + tipValue)
                result.derived.insert(.total)
                result.status = .repaired
            } else {
                result.status = .inconsistent
            }

        case let (nil, subtotal?, tax?):
            result.total = Self.roundedToCents(subtotal + tax + tipValue)
            result.derived.insert(.total)
            result.status = .repaired

        case let (total?, subtotal?, nil):
            if abs(total - subtotal - tipValue) <= Self.tolerance {
                result.status = .consistent
            } else {
                let derivedTax = Self.roundedToCents(total - subtotal - tipValue)
                result.tax = derivedTax > Self.tolerance ? derivedTax : nil
                if result.tax != nil { result.derived.insert(.tax) }
                result.status = result.tax == nil ? .inconsistent : .repaired
            }

        case let (total?, nil, tax?):
            let derivedSubtotal = Self.roundedToCents(total - tax - tipValue)
            if derivedSubtotal > Self.tolerance {
                result.subtotal = derivedSubtotal
                result.derived.insert(.subtotal)
                result.status = .repaired
            } else {
                result.status = .inconsistent
            }

        default:
            // One figure or none. Deriving anything here would be invention, not recovery —
            // a lone total says nothing about how it splits.
            result.status = .unverified
        }

        // Final guard, against the reconciled total rather than the raw one: a tax or tip at
        // or above the total is the grand total read into the wrong field, not a real figure.
        // Checked here so that a total which repair corrected upward — the case where the
        // total itself was the under-read value — does not cause a good component to be
        // discarded. Subtotal is exempt: it legitimately equals the total on a tax-free receipt.
        if let total = result.total {
            if let tax = result.tax, tax >= total - Self.tolerance { result.tax = nil }
            if let tip = result.tip, tip >= total - Self.tolerance { result.tip = nil }
        }

        return result
    }

    /// Derived figures are subtractions of decimal money in binary floating point, so
    /// `22.60 - 20.00` lands on 2.6000000000000014. Rounding here keeps that artefact out of
    /// the draft, the database and the displayed total — a receipt only ever has cents.
    private static func roundedToCents(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private static func balances(total: Double, subtotal: Double, tax: Double, tip: Double) -> Bool {
        abs(total - (subtotal + tax + tip)) <= tolerance
    }

    /// True when the figure read as the total sits at or below the subtotal while the parts
    /// sum to more. A purchase cannot cost less than the goods on it, so the figure is either
    /// the subtotal standing in for a total row that never reached OCR, or a smaller amount
    /// nearby that outranked it — a tax line, on a receipt whose total carries a label the
    /// token lists do not know.
    private static func totalCannotBeTheTotal(
        total: Double,
        subtotal: Double,
        tax: Double,
        tip: Double
    ) -> Bool {
        total <= subtotal + tolerance && (subtotal + tax + tip) > total + tolerance
    }
}

import Foundation

/// What the review screen tells the user about the figures in front of them.
///
/// Extracted from `AddReceiptViewModel` so it can be exercised without standing up a view
/// model, a container and a Core Data stack. It is a pure function of the form's contents:
/// same figures in, same advice out.
struct ReceiptReviewAdvice: Equatable {
    /// How much the extraction should be trusted, as a semantic value rather than an icon
    /// and a colour — the view decides how each one looks.
    enum Confidence: Equatable {
        /// Typed by hand, so there is no extraction to have an opinion about.
        case manualEntry
        /// Nothing on the form looks wrong.
        case clean
        /// At least one figure is missing, calculated, or doesn't add up.
        case needsAttention
    }

    /// The figures the advice is derived from, as they stand on the form.
    struct Input: Equatable {
        var isManualEntry: Bool
        var merchant: String
        var total: Double?
        var subtotal: Double?
        var tax: Double?
        var tip: Double?
        /// Non-empty lines recognition produced. A handful suggests a bad crop.
        var rawTextLineCount: Int
        /// Figures reconciliation computed rather than read off the paper.
        var derivedTotals: Set<ReceiptTotalsReconciler.Field>
        var totalsStatus: ReceiptTotalsReconciler.Status
    }

    let confidence: Confidence
    /// Specific things worth checking, in the order they should be read.
    let hints: [String]

    var title: String {
        switch confidence {
        case .manualEntry: "Manual entry"
        case .clean: "Extraction looks good"
        case .needsAttention: "Review recommended"
        }
    }

    var message: String {
        switch confidence {
        case .manualEntry: "Fill in the receipt fields yourself, then save."
        case .clean: "Merchant, total, and supporting details are ready for your confirmation."
        case .needsAttention: "OCR can be imperfect. Check the highlighted fields before saving."
        }
    }

    init(_ input: Input) {
        hints = Self.hints(for: input)
        confidence = input.isManualEntry ? .manualEntry : (hints.isEmpty ? .clean : .needsAttention)
    }

    /// Tolerance on the totals cross-check. Looser than the reconciler's own, because this
    /// is checking figures a person may still be editing rather than settling extraction.
    private static let sumTolerance = 0.05

    private static func hints(for input: Input) -> [String] {
        var hints: [String] = []

        if input.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hints.append("Merchant needs a quick check.")
        }

        if input.total == nil || input.total == 0 {
            hints.append("Total amount was not detected.")
        }

        if input.rawTextLineCount > 0, input.rawTextLineCount < 5 {
            hints.append("Only a few text lines were found. The crop or lighting may need another pass.")
        }

        // A total with no subtotal or tax beside it cannot be checked against anything. The
        // figure may well be right, but nothing on the receipt corroborates it, and that is
        // worth saying rather than presenting it with the same weight as one that adds up.
        if input.totalsStatus == .unverified, input.total != nil, input.subtotal == nil, input.tax == nil {
            hints.append("Only a total was found — there was nothing on the receipt to check it against.")
        }

        // A calculated figure is only as good as the two it came from, so name it rather
        // than presenting it with the same confidence as something read off the paper.
        if input.derivedTotals.contains(.total) {
            hints.append("Total was calculated from the subtotal and tax — the total line was not readable.")
        }
        if input.derivedTotals.contains(.subtotal) {
            hints.append("Subtotal was calculated from the total and tax.")
        }
        if input.derivedTotals.contains(.tax) {
            hints.append("Tax was calculated from the total and subtotal.")
        }

        if let total = input.total, let subtotal = input.subtotal {
            let expected = subtotal + (input.tax ?? 0) + (input.tip ?? 0)
            if abs(expected - total) > sumTolerance {
                hints.append("Subtotal, tax, and tip do not fully match the total.")
            }
        }

        return hints
    }
}

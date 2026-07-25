import Foundation
import Testing
@testable import privionyx

/// The advice shown above the review form. Previously computed inside `AddReceiptViewModel`,
/// where reaching it meant constructing a view model, a container and a Core Data stack.
@Suite("Receipt review advice")
struct ReceiptReviewAdviceTests {
    @Test("A receipt that adds up raises nothing")
    func cleanExtraction() {
        let advice = ReceiptReviewAdvice(.clean)

        #expect(advice.hints.isEmpty)
        #expect(advice.confidence == .clean)
        #expect(advice.title == "Extraction looks good")
    }

    @Test("Manual entry is never judged on extraction quality")
    func manualEntry() {
        // The fields are empty because the user has not typed them yet, not because
        // recognition failed — telling them to check the crop would be nonsense.
        var input = ReceiptReviewAdvice.Input.clean
        input.isManualEntry = true
        input.merchant = ""
        input.total = nil

        let advice = ReceiptReviewAdvice(input)

        #expect(advice.confidence == .manualEntry)
        #expect(advice.title == "Manual entry")
    }

    @Test("A missing merchant is called out")
    func missingMerchant() {
        var input = ReceiptReviewAdvice.Input.clean
        input.merchant = "   "

        #expect(ReceiptReviewAdvice(input).hints.contains { $0.contains("Merchant") })
    }

    @Test("A missing or zero total is called out", arguments: [nil, 0.0] as [Double?])
    func missingTotal(total: Double?) {
        var input = ReceiptReviewAdvice.Input.clean
        input.total = total

        let advice = ReceiptReviewAdvice(input)
        #expect(advice.hints.contains { $0.contains("Total amount was not detected") })
        #expect(advice.confidence == .needsAttention)
    }

    @Test("A handful of recognised lines suggests a bad crop")
    func sparseRecognition() {
        var input = ReceiptReviewAdvice.Input.clean
        input.rawTextLineCount = 3

        #expect(ReceiptReviewAdvice(input).hints.contains { $0.contains("crop or lighting") })
    }

    @Test("No lines at all is not reported as a sparse crop")
    func noRecognitionIsNotSparse() {
        // Zero lines means nothing was scanned — a manual or edited receipt — rather than a
        // scan that went badly.
        var input = ReceiptReviewAdvice.Input.clean
        input.rawTextLineCount = 0

        #expect(ReceiptReviewAdvice(input).hints.contains { $0.contains("crop or lighting") } == false)
    }

    @Test("Each calculated figure is named", arguments: [
        (ReceiptTotalsReconciler.Field.total, "Total was calculated"),
        (.subtotal, "Subtotal was calculated"),
        (.tax, "Tax was calculated")
    ])
    func derivedFiguresAreNamed(field: ReceiptTotalsReconciler.Field, expected: String) {
        var input = ReceiptReviewAdvice.Input.clean
        input.derivedTotals = [field]

        #expect(ReceiptReviewAdvice(input).hints.contains { $0.hasPrefix(expected) })
    }

    @Test("An uncorroborated total says so")
    func uncorroboratedTotal() {
        var input = ReceiptReviewAdvice.Input.clean
        input.subtotal = nil
        input.tax = nil
        input.totalsStatus = .unverified

        #expect(ReceiptReviewAdvice(input).hints.contains { $0.contains("nothing on the receipt to check it against") })
    }

    @Test("Figures that do not sum to the total are flagged")
    func sumMismatch() {
        var input = ReceiptReviewAdvice.Input.clean
        input.total = 20.00
        input.subtotal = 10.00
        input.tax = 1.30

        #expect(ReceiptReviewAdvice(input).hints.contains { $0.contains("do not fully match the total") })
    }

    @Test("Rounding noise is not treated as a mismatch")
    func toleratesRoundingNoise() {
        var input = ReceiptReviewAdvice.Input.clean
        input.total = 11.32
        input.subtotal = 10.00
        input.tax = 1.30

        #expect(ReceiptReviewAdvice(input).hints.isEmpty)
    }
}

private extension ReceiptReviewAdvice.Input {
    /// A scanned receipt whose figures reconcile — the baseline each test perturbs.
    static var clean: Self {
        .init(
            isManualEntry: false,
            merchant: "Corner Store",
            total: 11.30,
            subtotal: 10.00,
            tax: 1.30,
            tip: nil,
            rawTextLineCount: 24,
            derivedTotals: [],
            totalsStatus: .consistent
        )
    }
}

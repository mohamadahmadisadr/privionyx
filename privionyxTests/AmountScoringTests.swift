import Foundation
import Testing
@testable import privionyx

/// Total selection must not depend on how expensive the receipt is.
///
/// `amountScore` used to start at the figure's value in dollars while a "total" label was
/// worth a flat +80, so the size of the receipt decided how much the labels counted for. The
/// same three lines extracted correctly at $12.50 and returned the cash tendered at $420.
/// Reconciliation hides this whenever a subtotal or line items are present — it penalises
/// candidates far from `subtotal + tax` — so these fixtures deliberately have neither, which
/// is also what a small cash receipt actually looks like.
@Suite("Amount scoring")
struct AmountScoringTests {
    @Test("A cash sale takes the total, not the amount tendered", arguments: [
        (total: 12.50, tendered: 20.00, change: 7.50),
        (total: 42.00, tendered: 50.00, change: 8.00),
        (total: 420.00, tendered: 500.00, change: 80.00),
        (total: 4_200.00, tendered: 5_000.00, change: 800.00)
    ])
    func cashSaleTakesTheTotal(sale: (total: Double, tendered: Double, change: Double)) async {
        let text = """
            CORNER STORE
            TOTAL \(money(sale.total))
            CASH \(money(sale.tendered))
            CHANGE \(money(sale.change))
            """

        let parsed = await ReceiptParsingService().parse(rawText: text)

        // The point of the arguments list: one shape, four magnitudes, one answer each.
        #expect(parsed.amount == sale.total, "tendered \(sale.tendered) outranked the total")
    }

    @Test("A card tender larger than the total does not become the total")
    func cardTenderDoesNotWin() async {
        let text = """
            CORNER STORE
            TOTAL 420.00
            VISA TENDER 500.00
            """

        let parsed = await ReceiptParsingService().parse(rawText: text)

        #expect(parsed.amount == 420.00)
    }

    @Test("A labelled total beats a larger unlabelled figure")
    func labelBeatsBareMagnitude() async {
        let text = """
            CORNER STORE
            9876543210 00.00
            TOTAL 38.75
            1250.00
            """

        let parsed = await ReceiptParsingService().parse(rawText: text)

        #expect(parsed.amount == 38.75)
    }

    private func money(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

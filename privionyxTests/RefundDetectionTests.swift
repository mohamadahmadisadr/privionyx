import Foundation
import Testing
@testable import privionyx

/// Telling a return from a purchase.
///
/// A refund read as a positive amount is the worst kind of extraction error: it is not a
/// missing field the user notices and fills in, it is a confident figure with the sign
/// inverted, and it moves every total that touches it by twice the receipt's value.
@Suite("Refund detection")
struct RefundDetectionTests {
    private let extractor = AmountExtractor()

    // MARK: - Sign on a line

    @Test("A negative figure keeps its sign only where the sign is asked for")
    func signIsOptional() {
        let line = "MEMBER DISCOUNT           -20.00"

        #expect(extractor.signedAmounts(in: line) == [-20.00])
        // Everything that ranks and reconciles figures wants magnitudes.
        #expect(extractor.extractAmounts(in: line) == [20.00])
    }

    @Test("A minus written away from the figure is still the figure's sign")
    func spacedMinusIsRead() {
        #expect(extractor.signedAmounts(in: "TOTAL   - 56.49") == [-56.49])
    }

    @Test("A hyphen inside an identifier is not a minus sign")
    func hyphenInIdentifierIsNotASign() {
        // The digits here are an invoice number and a date, not money, and neither should
        // acquire a sign on the way past.
        #expect(extractor.signedAmounts(in: "TAXINV-001-1541798 03/03/18") == [])
        #expect(extractor.signedAmounts(in: "TERM-01                12.50") == [12.50])
    }

    // MARK: - Whole receipts

    @Test("A negative bottom line is a return")
    func negativeTotalIsARefund() {
        let lines = [
            "SUBTOTAL                   -49.99",
            "HST 13%                     -6.50",
            "TOTAL                      -56.49",
            "REFUND TO VISA              56.49"
        ]

        #expect(extractor.isRefund(from: lines, positionedLines: []))
    }

    @Test("An ordinary purchase is not a return")
    func purchaseIsNotARefund() {
        let lines = [
            "SUBTOTAL                    56.47",
            "HST 13%                      7.34",
            "TOTAL                       63.81"
        ]

        #expect(extractor.isRefund(from: lines, positionedLines: []) == false)
    }

    /// The distinction the whole check rests on: a negative figure among the items is an
    /// adjustment to something that still cost money.
    @Test("A negative row that is not the bottom line", arguments: [
        "MEMBER DISCOUNT           -20.00",
        "CASH ROUNDING              -0.02",
        "COUPON                     -3.50"
    ])
    func adjustmentsAreNotRefunds(row: String) {
        let lines = [
            "SUBTOTAL                  164.98",
            row,
            "HST 13%                    21.45",
            "TOTAL                     186.43"
        ]

        #expect(extractor.isRefund(from: lines, positionedLines: []) == false)
    }

    /// These carry the word "total" and are routinely printed negative, which is exactly the
    /// shape the check has to not fire on.
    @Test("A negative savings line is not a return", arguments: [
        "TOTAL SAVINGS             -14.20",
        "TOTAL REWARDS EARNED       -2.00"
    ])
    func savingsLinesAreNotRefunds(row: String) {
        let lines = [
            "SUBTOTAL                   56.47",
            "TOTAL                      63.81",
            row
        ]

        #expect(extractor.isRefund(from: lines, positionedLines: []) == false)
    }

    /// "subtotal" is one word. A receipt whose TOTAL row never reached recognition must not
    /// be read as a return on the strength of the row above it.
    @Test("A negative subtotal alone does not make a return")
    func subtotalAloneIsNotEnough() {
        #expect(extractor.isRefund(from: ["SUBTOTAL   -49.99"], positionedLines: []) == false)
    }

    // MARK: - Through the parser

    @Test("A return parses with its whole totals block negative")
    func refundParsesNegative() async {
        let parsed = await ReceiptParsingService().parse(rawText: """
        BRIGHTON HOME GOODS
        340 DANFORTH AVE

        *** RETURN ***
        TABLE LAMP                  49.99
        SUBTOTAL                   -49.99
        HST 13%                     -6.50
        TOTAL                      -56.49
        REFUND TO VISA              56.49
        """)

        #expect(parsed.amount == -56.49)
        #expect(parsed.subtotal == -49.99)
        #expect(parsed.tax == -6.50)
    }

    @Test("A purchase is untouched by the sign pass")
    func purchaseParsesPositive() async {
        let parsed = await ReceiptParsingService().parse(rawText: """
        NORTHSIDE HARDWARE
        1180 QUEEN ST W

        PRIMER 1L                   24.99
        SUBTOTAL                    24.99
        HST 13%                      3.25
        TOTAL                       28.24
        """)

        #expect(parsed.amount == 28.24)
        #expect(parsed.subtotal == 24.99)
        #expect(parsed.tax == 3.25)
    }

    /// The form has to be able to save what the parser now produces.
    @Test("A negative amount survives the round trip through the text field")
    func negativeAmountRoundTrips() {
        let typed = String(format: "%.2f", -56.49)

        #expect(typed == "-56.49")
        #expect(PrivionyxCurrencyParser.amount(from: typed) == -56.49)
    }
}

import Foundation
import Testing
@testable import privionyx

/// Reading an amount out of a text field. The separator rules are positional rather than
/// locale-driven, because a field can receive either convention whatever the device region.
@Suite("Currency input parsing")
struct PrivionyxCurrencyParserTests {
    @Test("Plain decimals", arguments: [
        ("12.50", 12.50),
        ("0.99", 0.99),
        ("20", 20.0),
        ("  34.10  ", 34.10),
        ("$45.00", 45.00),
        ("-5.00", -5.00)
    ])
    func plainDecimals(input: String, expected: Double) {
        #expect(PrivionyxCurrencyParser.amount(from: input) == expected)
    }

    @Test("Both separators present: the last one is the decimal mark", arguments: [
        ("1,234.56", 1234.56),
        ("1.234,56", 1234.56),
        ("1,234,567.89", 1234567.89),
        ("1.234.567,89", 1234567.89)
    ])
    func mixedSeparators(input: String, expected: Double) {
        #expect(PrivionyxCurrencyParser.amount(from: input) == expected)
    }

    @Test("Commas only: two trailing digits read as a decimal mark, otherwise grouping", arguments: [
        ("12,50", 12.50),
        ("1,234", 1234.0),
        ("1,234,567", 1234567.0)
    ])
    func commaOnly(input: String, expected: Double) {
        #expect(PrivionyxCurrencyParser.amount(from: input) == expected)
    }

    @Test("Nothing that denotes an amount", arguments: ["", "   ", "-", ".", ",", "abc", "$"])
    func rejectsNonAmounts(input: String) {
        // Mid-keystroke states in particular: a lone sign or separator must not read as zero,
        // which would let the Save button enable on an empty field.
        #expect(PrivionyxCurrencyParser.amount(from: input) == nil)
    }

    @Test("Currency symbols and stray characters are ignored")
    func stripsNoise() {
        #expect(PrivionyxCurrencyParser.amount(from: "CAD $ 1,299.99") == 1299.99)
    }
}

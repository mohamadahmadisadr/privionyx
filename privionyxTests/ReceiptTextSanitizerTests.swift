import Foundation
import Testing
@testable import privionyx

/// `ReceiptTextSanitizer.repairedDigitGlyphs` puts back digits that faded thermal print turned
/// into letters. The repair used to fire only between two digits, which is the one place a worn
/// print head is no more likely to strike than any other — the damage sits at the edge of the
/// number just as often, and there a period or a slash sat where the lookbehind wanted a digit.
///
/// Widening it means the repair now fires at the edge of a number, where the letter beside a
/// digit is just as likely to belong to a word. The cases that must *not* be touched are worth
/// pinning down as firmly as the ones that must.
@Suite("Receipt glyph repair")
struct ReceiptTextSanitizerTests {
    private let sanitizer = ReceiptTextSanitizer()

    @Test("A zero read as O between two digits is repaired")
    func zeroBetweenDigits() {
        #expect(sanitizer.repairedDigitGlyphs("TOTAL 1O.50") == "TOTAL 10.50")
    }

    @Test("A zero read as O in the cents is repaired")
    func zeroAfterDecimalPoint() {
        // The tax line from 24-faded-print-glyph-damage. The old lookbehind saw the period.
        #expect(sanitizer.repairedDigitGlyphs("HST 13% 2.O2") == "HST 13% 2.02")
    }

    @Test("A zero read as O ending an amount is repaired")
    func zeroEndingAnAmount() {
        #expect(sanitizer.repairedDigitGlyphs("SUBTOTAL 15.5O") == "SUBTOTAL 15.50")
    }

    @Test("Zeroes read as O in a date and a clock time are repaired")
    func zeroesInATimestamp() {
        #expect(sanitizer.repairedDigitGlyphs("03/1O/2026 O8:45") == "03/10/2026 08:45")
    }

    @Test("A one read as l or I between two digits is repaired")
    func oneBetweenDigits() {
        #expect(sanitizer.repairedDigitGlyphs("2l.99 and 3I.50") == "21.99 and 31.50")
    }

    @Test("A digit sitting in a word is left alone")
    func letterInsideAWord() {
        // Each of these has a letter beside a digit and none is damage. "H2O" is the one a
        // word-boundary rule would have got wrong: the O ends the token exactly as it does in
        // "7.5O", and only the H elsewhere in the token tells them apart.
        #expect(sanitizer.repairedDigitGlyphs("12oz H2O NO5") == "12oz H2O NO5")
    }

    @Test("A row of dashes is left alone")
    func separatorRow() {
        // Every character is punctuation the repair tolerates inside a figure, and the token
        // survives only because it has no digit to make it look like one.
        #expect(sanitizer.repairedDigitGlyphs("---------------") == "---------------")
    }

    @Test("Ordinary words are left alone")
    func ordinaryWords() {
        #expect(sanitizer.repairedDigitGlyphs("TORONTO ON SOURDOUGH LOAF") == "TORONTO ON SOURDOUGH LOAF")
    }

    @Test("Repairing twice changes nothing the first pass didn't")
    func idempotent() {
        // `DateExtractor` repairs lines the parsing service has usually repaired already.
        let once = sanitizer.repairedDigitGlyphs("SUBTOTAL 15.5O")
        #expect(sanitizer.repairedDigitGlyphs(once) == once)
    }

    @Test("A cleaned line carries the repair")
    func cleanedLineRepairsGlyphs() {
        #expect(sanitizer.cleanedReceiptLine("SOURDOUGH LOAF     7.5O") == "SOURDOUGH LOAF 7.50")
    }
}

import Foundation
import Testing
@testable import privionyx

/// `DateExtractor` reads the date off a receipt row, and both extraction paths now depend on
/// it — the deterministic parser and the Core ML field extractor, which previously handed a
/// whole OCR line to `DateFormatter.date(from:)`. That matches the entire string or nothing,
/// so a date with anything beside it never parsed. These cover the shapes that failed.
@Suite("Date extraction")
struct DateExtractorTests {
    @Test("A date preceded by a label is found")
    func labelledDate() throws {
        try expectDate(in: "Date: 06/15/2024", isYear: 2024, month: 6, day: 15)
    }

    @Test("A date followed by a clock time is found")
    func timestampedDate() throws {
        try expectDate(in: "06/15/2024 14:22", isYear: 2024, month: 6, day: 15)
    }

    @Test("A date surrounded by other fields is found")
    func dateAmongOtherText() throws {
        try expectDate(in: "TRANSACTION 2024-06-15 STORE 42", isYear: 2024, month: 6, day: 15)
    }

    @Test("A day-first date is read as day-first once month-first fails")
    func dayFirstDate() throws {
        // 15 is not a month, so MM/dd is rejected before dd/MM is tried.
        try expectDate(in: "15/06/2024", isYear: 2024, month: 6, day: 15)
    }

    @Test("A line with no date yields nothing")
    func noDate() {
        #expect(DateExtractor().extractDate(from: ["SUBTOTAL 12.99"]) == nil)
    }

    @Test("A date too old to be a receipt is rejected")
    func implausiblyOldDate() {
        // Guards the misparse case: a figure that happens to have a date's shape shouldn't
        // become the purchase date.
        #expect(DateExtractor().extractDate(from: ["01/01/1970"]) == nil)
    }

    @Test("A timestamped purchase beats a bare deadline printed above it")
    func purchaseBeatsDeadline() throws {
        let lines = [
            "Date limite pour retour",
            "07/20/2024",
            "ACHAT 06/15/2024 09:12"
        ]
        let date = try #require(DateExtractor().extractDate(from: lines))
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        #expect(parts.month == 6 && parts.day == 15, "the return-by date was taken as the purchase date")
    }

    private func expectDate(
        in line: String,
        isYear year: Int,
        month: Int,
        day: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let date = try #require(
            DateExtractor().extractDate(from: [line]),
            "no date found in \"\(line)\"",
            sourceLocation: sourceLocation
        )
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)

        #expect(parts.year == year, sourceLocation: sourceLocation)
        #expect(parts.month == month, sourceLocation: sourceLocation)
        #expect(parts.day == day, sourceLocation: sourceLocation)
    }
}

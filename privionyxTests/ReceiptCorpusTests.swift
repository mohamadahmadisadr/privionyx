import Foundation
import Testing
@testable import privionyx

/// Accuracy baseline for receipt extraction.
///
/// These tests measure rather than gate. They print a per-field and per-fixture report
/// on every run and only fail when the harness itself is broken (a fixture that will not
/// decode, or an empty text corpus). Thresholds get added once the refactor has moved the
/// numbers — locking in today's accuracy would only cement the current behaviour.
@Suite("Receipt extraction corpus")
struct ReceiptCorpusTests {
    /// Text fixtures isolate parsing from OCR: the input is hand-transcribed receipt text,
    /// so any failure here is an extraction bug and never a recognition bug.
    @Test("Text corpus baseline")
    func textCorpusBaseline() async throws {
        let fixtures = try ReceiptCorpus.textFixtures()
        try #require(fixtures.isEmpty == false, "no text fixtures in the bundle")

        let parser = ReceiptParsingService()
        var results: [FixtureResult] = []
        for fixture in fixtures {
            results.append(try await FixtureEvaluator.evaluate(fixture, using: parser))
        }

        let report = CorpusReport(title: "TEXT CORPUS (parsing only)", results: results)
        print(report.formatted())
    }

    /// Image fixtures measure the whole pipeline. The corpus starts empty — drop receipt
    /// photos and their `*.fixture.json` into `privionyxTests/Fixtures/Images/` to populate it.
    @Test("Image corpus baseline")
    func imageCorpusBaseline() async throws {
        let fixtures = try ReceiptCorpus.imageFixtures()
        guard fixtures.isEmpty == false else {
            print("\n=== IMAGE CORPUS ===\nempty — add receipt photos to measure the full pipeline\n")
            return
        }

        let parser = ReceiptParsingService()
        var results: [FixtureResult] = []
        for fixture in fixtures {
            results.append(try await FixtureEvaluator.evaluate(fixture, using: parser))
        }

        let report = CorpusReport(title: "IMAGE CORPUS (end to end)", results: results)
        print(report.formatted())
    }

    /// Guards the harness itself: every fixture in the bundle must decode and declare
    /// exactly one source. A silently skipped fixture would inflate every number above.
    @Test("Every fixture is well formed")
    func fixturesAreWellFormed() throws {
        let fixtures = try ReceiptCorpus.load()
        #expect(fixtures.isEmpty == false)
        for fixture in fixtures {
            #expect(fixture.name.isEmpty == false)
        }
    }
}

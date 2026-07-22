import Foundation
import UIKit
@testable import privionyx

/// Runs a fixture through the pipeline and grades the result against ground truth.
enum FixtureEvaluator {
    /// The parser has no way to say "not found" — it substitutes these instead. To measure
    /// recall honestly the harness has to translate them back into absence, otherwise a
    /// defaulted value scores as a wrong answer and hides how often extraction found nothing.
    ///
    /// Removing the need for this is itself a goal of the refactor: extracted fields should
    /// be optional and carry confidence, at which point these sentinels disappear.
    enum Sentinel {
        static let merchant = "Unknown Merchant"
        /// `ParsedReceiptData.amount` is non-optional and falls back to `.zero`.
        static let noAmount = 0.0
        /// `date` falls back to `.now`; anything within this window of the parse is a default.
        static let defaultedDateWindow: TimeInterval = 5
    }

    static func evaluate(
        _ fixture: ReceiptFixture,
        using parser: ReceiptParsingService
    ) async throws -> FixtureResult {
        let startedAt = Date()
        let start = ContinuousClock.now

        let parsed: ParsedReceiptData
        switch fixture.source {
        case let .rawText(text):
            parsed = await parser.parse(rawText: text)
        case let .image(url):
            let ocr = try await imageOCRResult(at: url)
            parsed = await parser.parse(ocrResult: ocr)
        }

        let elapsed = ContinuousClock.now - start
        let duration = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18

        return FixtureResult(
            name: fixture.name,
            outcomes: grade(fixture.expected, against: parsed, parseStartedAt: startedAt),
            actual: parsed,
            duration: duration
        )
    }

    static func grade(
        _ expected: ExpectedFields,
        against parsed: ParsedReceiptData,
        parseStartedAt: Date
    ) -> [FieldName: FieldOutcome] {
        let merchant = parsed.merchant == Sentinel.merchant ? nil : parsed.merchant
        let total = parsed.amount == Sentinel.noAmount ? nil : parsed.amount
        let dateWasDefaulted = abs(parsed.date.timeIntervalSince(parseStartedAt))
            < Sentinel.defaultedDateWindow
        let date = dateWasDefaulted ? nil : parsed.date

        return [
            .merchant: FieldComparison.text(expected: expected.merchant, actual: merchant),
            .date: FieldComparison.date(expected: expected.expectedDate, actual: date),
            .total: FieldComparison.money(expected: expected.total, actual: total),
            .subtotal: FieldComparison.money(expected: expected.subtotal, actual: parsed.subtotal),
            .tax: FieldComparison.money(expected: expected.tax, actual: parsed.tax),
            .tip: FieldComparison.money(expected: expected.tip, actual: parsed.tip),
            .category: FieldComparison.text(expected: expected.category, actual: parsed.category.rawValue),
            // Unlike every other field, a nil `lineItemSum` means "not asserted" rather than
            // "the receipt has none" — some receipts carry items this extractor is not yet
            // trying to model, such as negative discount rows, and claiming they must be
            // absent would assert the wrong thing.
            .lineItems: expected.lineItemSum == nil
                ? .notApplicable
                : FieldComparison.money(
                    expected: expected.lineItemSum,
                    actual: parsed.lineItems.isEmpty ? nil : parsed.lineItems.map(\.amount).reduce(0, +)
                )
        ]
    }

    private static func imageOCRResult(at url: URL) async throws -> OCRResult {
        guard let image = UIImage(contentsOfFile: url.path) else {
            throw OCRServiceError.unsupportedImage
        }
        return try await VisionOCRService().recognizeText(in: image)
    }
}

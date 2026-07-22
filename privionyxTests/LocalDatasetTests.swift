import Foundation
import Testing
import UIKit
@testable import privionyx

/// Runs the pipeline over a large local dataset that has no ground truth, checking
/// properties that must hold whatever the right answer is.
///
/// Labelling hundreds of receipts by hand is not worth it, and it is not what a bulk
/// dataset is good for. Every defect found in this pipeline so far announced itself as an
/// implausible *output* — a receipt dated year 23 AD, a $2026.05 total lifted from a
/// timestamp, a merchant that was really an item line. None of those need a label to
/// detect, only a statement of what a receipt cannot be. That scales to any number of
/// images and points at exactly which ones are worth labelling by hand afterwards.
///
/// The dataset lives outside the repository and is not distributed. Point
/// `PRIVIONYX_DATASET_DIR` at it, or leave the default; the suite skips when absent.
@Suite("Local dataset invariants")
struct LocalDatasetTests {
    /// Enough to be representative without turning a test run into a coffee break.
    static let sampleSize = 40

    static var datasetDirectory: URL? {
        let path = ProcessInfo.processInfo.environment["PRIVIONYX_DATASET_DIR"]
            ?? "/Users/mohamad/Code/ios/privionyx/archive"
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Things a receipt cannot be, regardless of what it says.
    enum Violation: String, CaseIterable {
        case implausibleDate = "date outside a plausible window"
        case implausibleTotal = "total negative or absurdly large"
        case merchantContainsPrice = "merchant carries a currency amount"
        case merchantStartsWithDigit = "merchant opens with a digit"
        case negativeComponent = "subtotal, tax or tip is negative"
        case componentExceedsTotal = "a component is larger than the total"
    }

    @Test("No receipt in the dataset produces an impossible field")
    func datasetProducesNothingImpossible() async throws {
        let directory = try #require(
            Self.datasetDirectory,
            "dataset not found — set PRIVIONYX_DATASET_DIR to run this suite"
        )

        let images = try Self.sampleImages(in: directory)
        try #require(images.isEmpty == false, "dataset directory contains no images")

        let ocr = VisionOCRService()
        let parser = ReceiptParsingService()

        var violations: [(name: String, violation: Violation, detail: String)] = []
        var unreadable: [String] = []
        var withoutTotal: [String] = []
        var unbalanced: [String] = []
        var totalDuration: TimeInterval = 0

        for url in images {
            guard let image = UIImage(contentsOfFile: url.path) else { continue }
            let name = url.lastPathComponent

            let started = Date()
            let start = ContinuousClock.now
            let result = try await ocr.recognizeText(in: image)
            let parsed = await parser.parse(ocrResult: result)
            let elapsed = ContinuousClock.now - start
            totalDuration += Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18

            if result.lines.count < 3 {
                unreadable.append(name)
                continue
            }

            for (violation, detail) in Self.violations(in: parsed, parseStartedAt: started) {
                violations.append((name, violation, detail))
            }

            if parsed.amount == 0 {
                withoutTotal.append(name)
            } else if let subtotal = parsed.subtotal {
                let sum = subtotal + (parsed.tax ?? 0) + (parsed.tip ?? 0)
                if abs(sum - parsed.amount) > ReceiptTotalsReconciler.tolerance {
                    unbalanced.append(name)
                }
            }
        }

        print(Self.report(
            count: images.count,
            violations: violations,
            unreadable: unreadable,
            withoutTotal: withoutTotal,
            unbalanced: unbalanced,
            totalDuration: totalDuration
        ))

        // Coverage rates are reported, not enforced: a blurred or blank photograph is a
        // legitimate reason to extract nothing, and this dataset is unlabelled so there is
        // no way to tell that apart from a miss. An impossible value is different — it is
        // wrong on its face, whatever the receipt said.
        #expect(violations.isEmpty, "\(violations.count) impossible field values")
    }

    private static func violations(
        in parsed: ParsedReceiptData,
        parseStartedAt: Date
    ) -> [(Violation, String)] {
        var found: [(Violation, String)] = []

        let dateWasDefaulted = abs(parsed.date.timeIntervalSince(parseStartedAt)) < 5
        if dateWasDefaulted == false {
            let year = Calendar.current.component(.year, from: parsed.date)
            let currentYear = Calendar.current.component(.year, from: .now)
            if year < currentYear - 30 || year > currentYear + 1 {
                found.append((.implausibleDate, "year \(year)"))
            }
        }

        if parsed.amount < 0 || parsed.amount > 100_000 {
            found.append((.implausibleTotal, String(format: "%.2f", parsed.amount)))
        }

        if parsed.merchant != "Unknown Merchant" {
            if parsed.merchant.range(of: #"\d[.,]\d{2}"#, options: .regularExpression) != nil {
                found.append((.merchantContainsPrice, parsed.merchant))
            }
            if parsed.merchant.range(of: #"^\d"#, options: .regularExpression) != nil {
                found.append((.merchantStartsWithDigit, parsed.merchant))
            }
        }

        for (label, value) in [("subtotal", parsed.subtotal), ("tax", parsed.tax), ("tip", parsed.tip)] {
            guard let value else { continue }
            if value < 0 {
                found.append((.negativeComponent, "\(label) \(String(format: "%.2f", value))"))
            }
            // Only meaningful once a total exists to compare against.
            if parsed.amount > 0, value > parsed.amount + ReceiptTotalsReconciler.tolerance {
                found.append((
                    .componentExceedsTotal,
                    "\(label) \(String(format: "%.2f", value)) > total \(String(format: "%.2f", parsed.amount))"
                ))
            }
        }

        return found
    }

    /// A deterministic spread across the dataset, so a run is reproducible and a fix can be
    /// checked against the same images that failed.
    private static func sampleImages(in directory: URL) throws -> [URL] {
        let all = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard all.count > sampleSize else { return all }
        let stride = all.count / sampleSize
        return (0..<sampleSize).map { all[$0 * stride] }
    }

    private static func report(
        count: Int,
        violations: [(name: String, violation: Violation, detail: String)],
        unreadable: [String],
        withoutTotal: [String],
        unbalanced: [String],
        totalDuration: TimeInterval
    ) -> String {
        var out = "\n=== LOCAL DATASET (\(count) receipts, unlabelled) ===\n"
        out += String(format: "mean %.0fms per receipt\n\n", totalDuration / Double(count) * 1000)

        out += "COVERAGE (reported, not enforced)\n"
        out += "  no text recognized : \(unreadable.count)/\(count)\n"
        out += "  no total found     : \(withoutTotal.count)/\(count)\n"
        out += "  totals not balanced: \(unbalanced.count)/\(count)\n\n"

        out += "IMPOSSIBLE VALUES: \(violations.count)\n"
        for violation in Violation.allCases {
            let hits = violations.filter { $0.violation == violation }
            guard hits.isEmpty == false else { continue }
            out += "  \(violation.rawValue): \(hits.count)\n"
            for hit in hits.prefix(8) {
                out += "      \(hit.name) — \(hit.detail)\n"
            }
        }

        if unreadable.isEmpty == false {
            out += "\nunreadable: \(unreadable.prefix(12).joined(separator: ", "))\n"
        }

        return out
    }
}

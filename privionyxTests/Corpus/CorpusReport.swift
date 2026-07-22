import Foundation
@testable import privionyx

/// How one extracted field compared to ground truth.
///
/// `missing` and `wrong` are kept apart deliberately: a field the parser never found
/// is a recall problem, a field it found incorrectly is a precision problem, and the
/// two call for opposite fixes. `spurious` catches the parser inventing a value for a
/// field the receipt does not have — the failure mode that silently corrupts data.
enum FieldOutcome: String, Sendable {
    case correct
    case wrong
    case missing
    case spurious
    /// Neither expected nor produced. Excluded from accuracy entirely.
    case notApplicable

    var countsTowardAccuracy: Bool { self != .notApplicable }
    var isCorrect: Bool { self == .correct }

    var symbol: String {
        switch self {
        case .correct: "OK  "
        case .wrong: "WRONG"
        case .missing: "MISS"
        case .spurious: "SPUR"
        case .notApplicable: "-   "
        }
    }
}

enum FieldName: String, CaseIterable, Sendable {
    case merchant, date, total, subtotal, tax, tip, category, lineItems
}

enum FieldComparison {
    /// Money is compared at cent resolution; anything finer is OCR noise, not a real difference.
    static let moneyTolerance = 0.005

    static func money(expected: Double?, actual: Double?) -> FieldOutcome {
        switch (expected, actual) {
        case (nil, nil): .notApplicable
        case (nil, .some): .spurious
        case (.some, nil): .missing
        case let (expected?, actual?): abs(expected - actual) < moneyTolerance ? .correct : .wrong
        }
    }

    static func date(expected: Date?, actual: Date?) -> FieldOutcome {
        switch (expected, actual) {
        case (nil, nil): .notApplicable
        case (nil, .some): .spurious
        case (.some, nil): .missing
        case let (expected?, actual?):
            Calendar.current.isDate(expected, inSameDayAs: actual) ? .correct : .wrong
        }
    }

    static func text(expected: String?, actual: String?) -> FieldOutcome {
        switch (expected, actual) {
        case (nil, nil): .notApplicable
        case (nil, .some): .spurious
        case (.some, nil): .missing
        case let (expected?, actual?):
            normalized(expected) == normalized(actual) ? .correct : .wrong
        }
    }

    /// Case, punctuation and spacing carry no meaning in a merchant name, so strip them
    /// before comparing — "TIM HORTONS #1234" and "Tim Hortons" should not count as a miss
    /// for a reason unrelated to extraction quality.
    static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }
}

struct FixtureResult: Sendable {
    let name: String
    let outcomes: [FieldName: FieldOutcome]
    let actual: ParsedReceiptData
    let duration: TimeInterval

    /// True when every applicable field matched — the metric that actually reflects
    /// "the user did not have to correct anything".
    var isFullyCorrect: Bool {
        outcomes.values.filter(\.countsTowardAccuracy).allSatisfy(\.isCorrect)
    }
}

struct CorpusReport: Sendable {
    let title: String
    let results: [FixtureResult]

    var fixtureCount: Int { results.count }

    var fullyCorrectRate: Double {
        guard results.isEmpty == false else { return 0 }
        return Double(results.filter(\.isFullyCorrect).count) / Double(results.count)
    }

    var medianDuration: TimeInterval {
        let sorted = results.map(\.duration).sorted()
        guard sorted.isEmpty == false else { return 0 }
        return sorted[sorted.count / 2]
    }

    func accuracy(for field: FieldName) -> (correct: Int, applicable: Int) {
        let outcomes = results.compactMap { $0.outcomes[field] }.filter(\.countsTowardAccuracy)
        return (outcomes.filter(\.isCorrect).count, outcomes.count)
    }

    func breakdown(for field: FieldName) -> [FieldOutcome: Int] {
        results.compactMap { $0.outcomes[field] }.reduce(into: [:]) { counts, outcome in
            counts[outcome, default: 0] += 1
        }
    }

    /// Human-readable baseline. Printed on every run so a change in accuracy is visible
    /// in the test log without any extra tooling.
    func formatted() -> String {
        guard results.isEmpty == false else {
            return "\n=== \(title) ===\nNo fixtures found. Nothing measured.\n"
        }

        var out = "\n=== \(title) ===\n"
        out += "\(fixtureCount) fixtures · "
        out += "fully correct: \(percent(fullyCorrectRate)) · "
        out += "median \(String(format: "%.0f", medianDuration * 1000))ms\n\n"

        out += "PER-FIELD ACCURACY\n"
        out += pad("field", 10) + pad("acc", 9) + pad("ok", 5) + pad("wrong", 7)
        out += pad("miss", 6) + pad("spur", 6) + "n/a\n"
        for field in FieldName.allCases {
            let (correct, applicable) = accuracy(for: field)
            let counts = breakdown(for: field)
            let rate = applicable == 0 ? "—" : percent(Double(correct) / Double(applicable))
            out += pad(field.rawValue, 10) + pad(rate, 9)
            out += pad("\(counts[.correct] ?? 0)", 5)
            out += pad("\(counts[.wrong] ?? 0)", 7)
            out += pad("\(counts[.missing] ?? 0)", 6)
            out += pad("\(counts[.spurious] ?? 0)", 6)
            out += "\(counts[.notApplicable] ?? 0)\n"
        }

        out += "\nPER-FIXTURE\n"
        for result in results.sorted(by: { $0.name < $1.name }) {
            let flag = result.isFullyCorrect ? "PASS" : "FAIL"
            out += "\(flag)  \(result.name)\n"
            guard result.isFullyCorrect == false else { continue }
            for field in FieldName.allCases {
                guard let outcome = result.outcomes[field], outcome.isCorrect == false,
                      outcome.countsTowardAccuracy else { continue }
                out += "      \(outcome.symbol) \(pad(field.rawValue, 10))"
                out += "got: \(describe(field, in: result.actual))\n"
            }
        }

        return out + "\n"
    }

    private func describe(_ field: FieldName, in parsed: ParsedReceiptData) -> String {
        switch field {
        case .merchant: parsed.merchant
        case .date: ISO8601DateFormatter().string(from: parsed.date)
        case .total: String(format: "%.2f", parsed.amount)
        case .subtotal: parsed.subtotal.map { String(format: "%.2f", $0) } ?? "nil"
        case .tax: parsed.tax.map { String(format: "%.2f", $0) } ?? "nil"
        case .tip: parsed.tip.map { String(format: "%.2f", $0) } ?? "nil"
        case .category: parsed.category.rawValue
        case .lineItems:
            parsed.lineItems.isEmpty
                ? "none"
                : String(format: "%d items, %.2f", parsed.lineItems.count,
                         parsed.lineItems.map(\.amount).reduce(0, +))
        }
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func pad(_ value: String, _ width: Int) -> String {
        value.padding(toLength: max(width, value.count + 1), withPad: " ", startingAt: 0)
    }
}

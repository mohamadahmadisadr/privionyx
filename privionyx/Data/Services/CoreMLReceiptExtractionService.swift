import CoreML
import Foundation

enum ReceiptFieldLabel: String, CaseIterable {
    case merchant
    case total
    case subtotal
    case tax
    case tip
    case date
    case ignore
}

struct CoreMLReceiptExtractionService {
    private let model: MLModel?
    /// The same reader the deterministic path uses, rather than a second one here. See
    /// `parseDate(from:)`.
    private let dateExtractor = DateExtractor()

    init(bundle: Bundle = .main) {
        if let modelURL = bundle.url(forResource: "ReceiptFieldExtractor", withExtension: "mlmodelc") {
            model = try? MLModel(contentsOf: modelURL)
        } else {
            model = nil
        }
    }

    func extract(from lines: [OCRTextLine]) -> ReceiptMLExtraction? {
        guard let model, lines.isEmpty == false else { return nil }

        let predictions = lines.compactMap { line -> (ReceiptFieldLabel, OCRTextLine, Double)? in
            guard let prediction = predictLabel(for: line, using: model) else { return nil }
            return (prediction.label, line, prediction.confidence)
        }

        guard predictions.isEmpty == false else { return nil }

        let merchant = bestLine(for: .merchant, in: predictions)
        let amount = bestLine(for: .total, in: predictions).flatMap(parseAmount)
        let subtotal = bestLine(for: .subtotal, in: predictions).flatMap(parseAmount)
        let tax = bestLine(for: .tax, in: predictions).flatMap(parseAmount)
        let tip = bestLine(for: .tip, in: predictions).flatMap(parseAmount)
        let date = bestLine(for: .date, in: predictions).flatMap(parseDate)

        let extraction = ReceiptMLExtraction(
            merchant: merchant,
            amount: amount,
            subtotal: subtotal,
            tax: tax,
            tip: tip,
            date: date
        )

        return extraction.hasUsefulValues ? extraction : nil
    }

    private func predictLabel(for line: OCRTextLine, using model: MLModel) -> (label: ReceiptFieldLabel, confidence: Double)? {
        guard let provider = makeFeatureProvider(for: line),
              let output = try? model.prediction(from: provider) else {
            return nil
        }

        if let labelName = output.featureValue(for: "label")?.stringValue,
           let label = ReceiptFieldLabel(rawValue: labelName) {
            let confidence = output.featureValue(for: "labelProbability")?.dictionaryValue[labelName] as? Double ?? 0.5
            return (label, confidence)
        }

        if let labelName = output.featureValue(for: "classLabel")?.stringValue,
           let label = ReceiptFieldLabel(rawValue: labelName) {
            let confidence = output.featureValue(for: "classProbability")?.dictionaryValue[labelName] as? Double ?? 0.5
            return (label, confidence)
        }

        return nil
    }

    private func makeFeatureProvider(for line: OCRTextLine) -> MLDictionaryFeatureProvider? {
        let text = line.text
        let lowercased = text.lowercased()
        let hasAmount = text.range(of: #"\d+[.,]\d{2}"#, options: .regularExpression) != nil
        let hasDate = text.range(of: #"\d{1,2}[/-]\d{1,2}[/-]\d{2,4}"#, options: .regularExpression) != nil
        let features: [String: Any] = [
            "text": text,
            "minX": Double(line.minX),
            "maxX": Double(line.maxX),
            "midY": Double(line.midY),
            "textLength": Double(text.count),
            "hasAmount": hasAmount ? 1.0 : 0.0,
            "hasDate": hasDate ? 1.0 : 0.0,
            "containsTotal": lowercased.contains("total") ? 1.0 : 0.0,
            "containsSubtotal": (lowercased.contains("subtotal") || lowercased.contains("sub total")) ? 1.0 : 0.0,
            "containsTax": (lowercased.contains("tax") || lowercased.contains("hst") || lowercased.contains("gst")) ? 1.0 : 0.0,
            "containsTip": (lowercased.contains("tip") || lowercased.contains("gratuity")) ? 1.0 : 0.0
        ]

        return try? MLDictionaryFeatureProvider(dictionary: features)
    }

    private func bestLine(for label: ReceiptFieldLabel, in predictions: [(ReceiptFieldLabel, OCRTextLine, Double)]) -> String? {
        predictions
            .filter { $0.0 == label }
            .max { lhs, rhs in lhs.2 < rhs.2 }?
            .1.text
    }

    private func parseAmount(from line: String) -> Double? {
        let pattern = #"\$?\d+(?:[,\s]\d{3})*(?:[.,]\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.matches(in: line, range: range).last,
              let matchRange = Range(match.range, in: line) else {
            return nil
        }

        let value = line[matchRange]
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: " ", with: "")
        let normalized = value.contains(".")
            ? value.replacingOccurrences(of: ",", with: "")
            : value.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    /// Reads the date out of a whole OCR row.
    ///
    /// This used to hand the row straight to `DateFormatter.date(from:)`, which matches the
    /// entire string or nothing — so "Date: 03/14/2026" and "03/14/2026 14:22" both failed,
    /// and the model's date label could never produce a value. `DateExtractor` is what the
    /// deterministic path already uses: it pulls candidate segments out of the line, tries a
    /// wider set of formats, and rejects dates too far from today to be a purchase.
    private func parseDate(from line: String) -> Date? {
        dateExtractor.extractDate(from: [line])
    }
}

private extension ReceiptMLExtraction {
    var hasUsefulValues: Bool {
        merchant?.isEmpty == false ||
        amount != nil ||
        subtotal != nil ||
        tax != nil ||
        tip != nil ||
        date != nil
    }
}

extension CoreMLReceiptExtractionService: ReceiptMLExtractor {}

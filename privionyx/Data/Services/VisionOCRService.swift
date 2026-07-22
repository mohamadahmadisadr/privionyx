import CoreGraphics
import UIKit
import Vision

struct VisionOCRService {
    private let imageProcessor: ReceiptImageProcessor
    private static let preferredLanguages = ["en-CA", "fr-CA", "en-US"]

    /// Below this many rows the page is treated as unreadable and retried once on a
    /// contrast-boosted copy. Faded thermal paper is the case this exists for.
    private static let sparseRowThreshold = 5

    private static let customReceiptWords = [
        "subtotal", "sub total", "tax", "hst", "gst", "tvq", "vat", "tip", "gratuity",
        "total", "amount due", "balance due", "debit", "credit", "receipt", "invoice",
        "petro-canada", "tim hortons", "walmart", "costco", "whole foods", "no frills",
        "loblaws", "metro", "shell", "esso", "amazon", "mastercard", "visa",
        "transaction", "approval", "purchase", "interac", "subtotal", "sub-total",
        "service", "restaurant", "merci", "total due", "net sales", "cashier",
        "merchant", "terminal", "reference", "cardholder", "change due", "paid"
    ]

    init(imageProcessor: ReceiptImageProcessor = ReceiptImageProcessor()) {
        self.imageProcessor = imageProcessor
    }

    /// Recognizes a receipt as a list of visual rows.
    ///
    /// A single recognition pass is used. An earlier version ran six preprocessing variants
    /// and merged the results, but the merge keyed on the recognized text itself, so
    /// variants that disagreed produced separate entries rather than voting — a 50-row
    /// receipt came back as 175 rows carrying seven spellings of its own header. One pass
    /// over a well-prepared image is both cleaner and six times cheaper.
    func recognizeText(in image: UIImage) async throws -> OCRResult {
        // Downscale before anything else so every later copy is of the smaller image.
        let normalizedImage = imageProcessor.normalizedImage(
            imageProcessor.downscaledForRecognition(image)
        )

        var fragments = try await Self.recognizedFragments(in: normalizedImage)
        if Self.assembleRows(fragments).count < Self.sparseRowThreshold {
            let enhanced = imageProcessor.enhanceReceiptImage(normalizedImage)
            let enhancedFragments = try await Self.recognizedFragments(in: enhanced)
            if enhancedFragments.count > fragments.count {
                fragments = enhancedFragments
            }
        }

        let rows = Self.assembleRows(fragments)
        return OCRResult(rawText: rows.map(\.text).joined(separator: "\n"), lines: rows)
    }

    // MARK: - Recognition

    private static func recognizedFragments(in image: UIImage) async throws -> [RecognizedFragment] {
        guard let cgImage = image.cgImage else {
            throw OCRServiceError.unsupportedImage
        }

        let documentFragments = try await recognizedDocumentFragments(in: cgImage)
        if documentFragments.isEmpty == false {
            return documentFragments
        }

        return try recognizedTextFragments(in: cgImage)
    }

    private static func recognizedDocumentFragments(in cgImage: CGImage) async throws -> [RecognizedFragment] {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.automaticallyDetectLanguage = false
        request.textRecognitionOptions.minimumTextHeightFraction = 0.008
        request.textRecognitionOptions.customWords = Self.customReceiptWords
        request.textRecognitionOptions.recognitionLanguages = Self.preferredLanguages
            .map(Locale.Language.init(identifier:))

        let observations = try await request.perform(on: cgImage, orientation: nil)
        return observations.flatMap { observation in
            observation.document.text.lines.compactMap { line in
                Self.fragment(text: line.transcript, box: line.boundingRegion.boundingBox.cgRect)
            }
        }
    }

    private static func recognizedTextFragments(in cgImage: CGImage) throws -> [RecognizedFragment] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = Self.preferredLanguages
        request.customWords = Self.customReceiptWords
        request.minimumTextHeight = 0.008

        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return Self.fragment(text: candidate.string, box: observation.boundingBox)
        }
    }

    private static func fragment(text: String, box: CGRect) -> RecognizedFragment? {
        let cleaned = Self.cleanedOCRText(text)
        guard cleaned.isEmpty == false else { return nil }

        return RecognizedFragment(
            text: cleaned,
            minX: box.minX,
            maxX: box.maxX,
            midY: box.midY,
            height: box.height
        )
    }

    // MARK: - Row assembly

    /// Groups fragments into visual rows, then joins each row left to right.
    ///
    /// Grouping is a single ordered sweep rather than a sort predicate. The previous code
    /// sorted with "same row if |Δy| < 0.012" — a fixed threshold close enough to the line
    /// spacing that `SUBTOTAL ~ 228.02` and `TAX ~ 228.02` while `SUBTOTAL ≁ TAX`. A
    /// non-transitive predicate leaves `sorted(by:)` undefined, which is how the label and
    /// amount columns ended up interleaved and every tax lookup read its neighbour's value.
    static func assembleRows(_ fragments: [RecognizedFragment]) -> [OCRTextLine] {
        guard fragments.isEmpty == false else { return [] }

        // Vision's origin is bottom-left, so descending midY is top-of-page first.
        let ordered = fragments.sorted { $0.midY > $1.midY }
        let tolerance = rowTolerance(for: fragments)

        var rows: [[RecognizedFragment]] = []
        var current: [RecognizedFragment] = []
        var anchorY: CGFloat = 0

        for fragment in ordered {
            if current.isEmpty || abs(fragment.midY - anchorY) <= tolerance {
                current.append(fragment)
                // Track the running mean so a skewed receipt, where one row drifts
                // vertically across the page, still accumulates into a single row.
                anchorY = current.map(\.midY).reduce(0, +) / CGFloat(current.count)
            } else {
                rows.append(current)
                current = [fragment]
                anchorY = fragment.midY
            }
        }
        if current.isEmpty == false {
            rows.append(current)
        }

        return rows.compactMap(Self.joinRow)
    }

    /// Half the median glyph height: tall enough to pull a label and its amount together,
    /// short enough to keep adjacent rows apart, and expressed relative to the text so it
    /// holds for both a 500px template and a 5712px camera capture.
    private static func rowTolerance(for fragments: [RecognizedFragment]) -> CGFloat {
        let heights = fragments.map(\.height).filter { $0 > 0 }.sorted()
        guard heights.isEmpty == false else { return 0.006 }
        return max(heights[heights.count / 2] * 0.5, 0.002)
    }

    private static func joinRow(_ row: [RecognizedFragment]) -> OCRTextLine? {
        let ordered = row.sorted { $0.minX < $1.minX }
        let text = Self.cleanedOCRText(ordered.map(\.text).joined(separator: " "))
        guard text.isEmpty == false, Self.isLikelyUsefulOCRLine(text) else { return nil }

        return OCRTextLine(
            text: text,
            minX: ordered.map(\.minX).min() ?? 0,
            maxX: ordered.map(\.maxX).max() ?? 0,
            midY: ordered.map(\.midY).reduce(0, +) / CGFloat(ordered.count),
            height: ordered.map(\.height).max() ?? 0
        )
    }

    // MARK: - Text cleanup

    private static func cleanedOCRText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[\u{00A0}\t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[|]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([.,:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([.,:])\s+"#, with: "$1 ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A joined row is longer than a single fragment, so the length ceiling is higher than
    /// the per-fragment limit it replaces.
    private static func isLikelyUsefulOCRLine(_ line: String) -> Bool {
        let letters = line.filter(\.isLetter).count
        let digits = line.filter(\.isNumber).count
        guard letters + digits > 0 else { return false }
        guard line.count <= 200 else { return false }
        if line.count <= 2, digits == 0 { return false }
        return true
    }
}

struct RecognizedFragment {
    let text: String
    let minX: CGFloat
    let maxX: CGFloat
    let midY: CGFloat
    let height: CGFloat
}

extension VisionOCRService: OCRService {}

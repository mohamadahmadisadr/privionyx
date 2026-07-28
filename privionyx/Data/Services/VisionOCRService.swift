import CoreGraphics
import UIKit
import Vision

nonisolated struct VisionOCRService {
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
        let normalizedImage = imageProcessor.preparedForRecognition(image)

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

        // `RecognizeDocumentsRequest` understands a receipt as a document — it groups text
        // into lines itself and reads faded thermal paper markedly better. It is iOS 26 only,
        // so it is an upgrade rather than a requirement: below that, and whenever it comes
        // back with nothing, the classic text request underneath does the same job.
        if #available(iOS 26.0, *) {
            let documentFragments = try await recognizedDocumentFragments(in: cgImage)
            if documentFragments.isEmpty == false {
                return documentFragments
            }
        }

        return try recognizedTextFragments(in: cgImage)
    }

    @available(iOS 26.0, *)
    private static func recognizedDocumentFragments(in cgImage: CGImage) async throws -> [RecognizedFragment] {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.automaticallyDetectLanguage = false
        request.textRecognitionOptions.minimumTextHeightFraction = 0.008
        request.textRecognitionOptions.customWords = Self.customReceiptWords
        request.textRecognitionOptions.recognitionLanguages = Self.preferredLanguages
            .map(Locale.Language.init(identifier:))

        let observations = try await request.perform(on: cgImage, orientation: nil)
        let quads = observations.flatMap { observation in
            observation.document.text.lines.compactMap { line in
                Self.quad(text: line.transcript, corners: line.boundingRegion.normalizedPoints)
            }
        }
        return Self.uprightFragments(from: quads)
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

        let quads = (request.results ?? []).compactMap { observation -> RecognizedQuad? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return Self.quad(
                text: candidate.string,
                topLeft: observation.topLeft,
                topRight: observation.topRight,
                bottomRight: observation.bottomRight,
                bottomLeft: observation.bottomLeft
            )
        }
        return Self.uprightFragments(from: quads)
    }

    private static func quad(text: String, corners: [SIMD2<Float>]) -> RecognizedQuad? {
        // Vision orders a region's points from its top-left, clockwise in the text's frame.
        guard corners.count == 4 else { return nil }
        let points = corners.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        return Self.quad(
            text: text,
            topLeft: points[0],
            topRight: points[1],
            bottomRight: points[2],
            bottomLeft: points[3]
        )
    }

    private static func quad(
        text: String,
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint
    ) -> RecognizedQuad? {
        let cleaned = Self.cleanedOCRText(text)
        guard cleaned.isEmpty == false else { return nil }

        return RecognizedQuad(
            text: cleaned,
            topLeft: topLeft,
            topRight: topRight,
            bottomRight: bottomRight,
            bottomLeft: bottomLeft
        )
    }

    // MARK: - Page rotation

    /// Rewrites every line's geometry into the frame the text itself reads in.
    ///
    /// A receipt is a long strip, so it is routinely photographed lying sideways — and a
    /// sideways photo of an upright phone carries no EXIF rotation to correct it. Vision
    /// transcribes such a page perfectly well, because it detects each line's rotation on
    /// its own, but it reports the boxes in image coordinates. Row assembly groups by `y`,
    /// so on a sideways page every line shares a `y` and the whole receipt collapses into
    /// one row: a 50-row receipt arrived at the parser as a single line reading
    /// "and $50.46 $50.46 $5.81 $50.46 $1.729 29.186 Unleaded", from which it took the
    /// litre count as the total.
    ///
    /// The corner order is what makes this recoverable. Vision labels the corners in the
    /// text's own frame, so `topLeft → topRight` runs along the reading direction whatever
    /// the paper was doing, and rotating every corner by that angle restores a page whose
    /// rows run left to right. Nothing is re-recognized — the transcripts were already
    /// right, only their coordinates were in the wrong frame.
    static func uprightFragments(from quads: [RecognizedQuad]) -> [RecognizedFragment] {
        let direction = Self.readingDirection(of: quads)
        return Self.framedToPaper(quads.map { $0.rotated(onto: direction) })
    }

    /// Rescales the page so its coordinates measure the receipt rather than the photograph.
    ///
    /// Everything downstream reads these numbers as positions on the paper: the totals block
    /// sits below `midY` 0.42, the amount column reaches past `maxX` 0.58. That only holds
    /// when the receipt fills the frame. A strip photographed on a table with margins around
    /// it spanned x 0.29 to 0.57, so its amount column failed the 0.58 test on every single
    /// row — the totals block was never identified as one, and an item price was returned as
    /// the total of the receipt.
    ///
    /// The two axes are scaled independently on purpose. Aspect ratio carries no meaning
    /// here; each rule reads one axis alone, and each wants a fraction of the receipt.
    private static func framedToPaper(_ fragments: [RecognizedFragment]) -> [RecognizedFragment] {
        guard fragments.isEmpty == false else { return fragments }

        let minX = fragments.map(\.minX).min() ?? 0
        let maxX = fragments.map(\.maxX).max() ?? 1
        let minY = fragments.map { $0.midY - $0.height / 2 }.min() ?? 0
        let maxY = fragments.map { $0.midY + $0.height / 2 }.max() ?? 1

        // A receipt too narrow to have columns, or a single recognized row, has no spread to
        // normalize against; stretching it would turn rounding noise into layout.
        let spanX = maxX - minX
        let spanY = maxY - minY
        guard spanX > 0.05, spanY > 0.05 else { return fragments }

        return fragments.map { fragment in
            RecognizedFragment(
                text: fragment.text,
                minX: (fragment.minX - minX) / spanX,
                maxX: (fragment.maxX - minX) / spanX,
                midY: (fragment.midY - minY) / spanY,
                height: fragment.height / spanY
            )
        }
    }

    /// The page's reading direction, snapped to the nearest quarter turn.
    ///
    /// Baselines are summed rather than averaged by angle so that longer lines, which carry
    /// far more directional evidence than a stray one-glyph fragment, dominate the result.
    /// Snapping is safe because a page is either upright or laid on its side; the residual
    /// few degrees of skew is what `assembleRows` already tolerates.
    private static func readingDirection(of quads: [RecognizedQuad]) -> CGVector {
        let baseline = quads.reduce(into: CGVector.zero) { total, quad in
            total.dx += quad.topRight.x - quad.topLeft.x
            total.dy += quad.topRight.y - quad.topLeft.y
        }

        if abs(baseline.dx) >= abs(baseline.dy) {
            return CGVector(dx: baseline.dx < 0 ? -1 : 1, dy: 0)
        }
        return CGVector(dx: 0, dy: baseline.dy < 0 ? -1 : 1)
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
        let text = ReceiptLabelRepair.repaired(
            Self.cleanedOCRText(ordered.map(\.text).joined(separator: " "))
        )
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

/// One recognized line, kept as the quadrilateral it occupies rather than an upright box.
///
/// The corners are ordered in the text's own frame — top-left, top-right, bottom-right,
/// bottom-left as the reader sees them — which is the only reason the page's rotation can
/// be recovered from them at all.
nonisolated struct RecognizedQuad {
    let text: String
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomRight: CGPoint
    let bottomLeft: CGPoint

    /// Projects the quad onto a frame whose x axis is `direction`, collapsing it back to
    /// the upright box the rest of the pipeline expects. A `direction` of (1, 0) is the
    /// identity, so an already-upright page pays nothing for this.
    ///
    /// The result is rebased into the unit square. Rotating alone sends half the quarter
    /// turns into negative coordinates, and downstream rules read those numbers as absolute
    /// positions on the page — "the totals block sits below `midY` 0.42", "the amount column
    /// reaches past `maxX` 0.58". A page whose x ran from -0.71 to -0.40 failed the second
    /// of those on every row, so the totals block was never recognized as one.
    func rotated(onto direction: CGVector) -> RecognizedFragment {
        // The text's "up" is its reading direction turned a quarter turn counter-clockwise.
        let up = CGVector(dx: -direction.dy, dy: direction.dx)
        // A quarter turn of the unit square lands it in [-1, 0] exactly when the axis it
        // maps onto points backwards, so undoing it is a translation by one whole square.
        let xOffset: CGFloat = direction.dx + direction.dy < 0 ? 1 : 0
        let yOffset: CGFloat = up.dx + up.dy < 0 ? 1 : 0

        let corners = [topLeft, topRight, bottomRight, bottomLeft]
        let xs = corners.map { $0.x * direction.dx + $0.y * direction.dy + xOffset }
        let ys = corners.map { $0.x * up.dx + $0.y * up.dy + yOffset }

        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0

        return RecognizedFragment(
            text: text,
            minX: xs.min() ?? 0,
            maxX: xs.max() ?? 0,
            midY: (minY + maxY) / 2,
            height: maxY - minY
        )
    }
}

extension VisionOCRService: OCRService {}

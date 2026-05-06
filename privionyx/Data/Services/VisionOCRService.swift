import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import UIKit
import Vision

struct OCRTextLine: Hashable {
    let text: String
    let minX: CGFloat
    let maxX: CGFloat
    let midY: CGFloat
}

struct ReceiptQuadrilateral: Hashable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    static let `default` = ReceiptQuadrilateral(
        topLeft: CGPoint(x: 0.08, y: 0.94),
        topRight: CGPoint(x: 0.92, y: 0.94),
        bottomRight: CGPoint(x: 0.92, y: 0.08),
        bottomLeft: CGPoint(x: 0.08, y: 0.08)
    )
}

enum OCRServiceError: LocalizedError {
    case unsupportedImage

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            "The selected image could not be processed."
        }
    }
}

struct OCRResult {
    let rawText: String
    let lines: [OCRTextLine]
}

struct VisionOCRService {
    private let context = CIContext(options: nil)
    private static let preferredLanguages = ["en-CA", "fr-CA", "en-US"]
    private static let customReceiptWords = [
        "subtotal", "sub total", "tax", "hst", "gst", "tvq", "vat", "tip", "gratuity",
        "total", "amount due", "balance due", "debit", "credit", "receipt", "invoice",
        "petro-canada", "tim hortons", "walmart", "costco", "whole foods", "no frills",
        "loblaws", "metro", "shell", "esso", "amazon", "mastercard", "visa",
        "transaction", "approval", "purchase", "interac", "subtotal", "sub-total",
        "service", "restaurant", "merci", "total due", "net sales", "cashier",
        "merchant", "terminal", "reference", "cardholder", "change due", "paid"
    ]

    func normalizedImage(_ image: UIImage) -> UIImage {
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = image.scale

        let renderer = UIGraphicsImageRenderer(size: image.size, format: rendererFormat)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    func enhanceReceiptImage(_ image: UIImage) -> UIImage {
        let normalizedImage = normalizedImage(image)

        guard let inputImage = CIImage(image: normalizedImage) else {
            return normalizedImage
        }

        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = inputImage
        colorControls.saturation = 0
        colorControls.contrast = 1.18
        colorControls.brightness = 0.02

        let sharpen = CIFilter.sharpenLuminance()
        sharpen.inputImage = colorControls.outputImage
        sharpen.sharpness = 0.35

        guard let outputImage = sharpen.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return normalizedImage
        }

        return UIImage(cgImage: cgImage, scale: normalizedImage.scale, orientation: .up)
    }

    func thresholdedReceiptImage(_ image: UIImage) -> UIImage {
        let normalizedImage = normalizedImage(image)

        guard let inputImage = CIImage(image: normalizedImage) else {
            return normalizedImage
        }

        let mono = CIFilter.colorControls()
        mono.inputImage = inputImage
        mono.saturation = 0
        mono.contrast = 1.45
        mono.brightness = 0.03

        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = mono.outputImage
        exposure.ev = 0.55

        guard let outputImage = exposure.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return normalizedImage
        }

        return UIImage(cgImage: cgImage, scale: normalizedImage.scale, orientation: .up)
    }

    func upscaledReceiptImage(_ image: UIImage) -> UIImage {
        let normalizedImage = normalizedImage(image)
        let targetSize = CGSize(width: normalizedImage.size.width * 1.35, height: normalizedImage.size.height * 1.35)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            normalizedImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    func detectReceiptQuadrilateral(in image: UIImage) async -> ReceiptQuadrilateral? {
        let normalizedImage = normalizedImage(image)

        guard let cgImage = normalizedImage.cgImage else {
            return nil
        }

        return await Task.detached(priority: .userInitiated) {
            let request = VNDetectRectanglesRequest()
            request.maximumObservations = 1
            request.minimumConfidence = 0.55
            request.minimumAspectRatio = 0.15
            request.maximumAspectRatio = 1
            request.quadratureTolerance = 22

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])

            guard let observation = request.results?.first else {
                return nil
            }

            return ReceiptQuadrilateral(
                topLeft: observation.topLeft,
                topRight: observation.topRight,
                bottomRight: observation.bottomRight,
                bottomLeft: observation.bottomLeft
            )
        }
        .value
    }

    func cropReceiptImage(_ image: UIImage, quadrilateral: ReceiptQuadrilateral) -> UIImage {
        let normalizedImage = normalizedImage(image)

        guard let inputImage = CIImage(image: normalizedImage) else {
            return normalizedImage
        }

        let points = denormalizedPoints(for: quadrilateral, imageSize: normalizedImage.size)
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = inputImage
        filter.topLeft = points.topLeft
        filter.topRight = points.topRight
        filter.bottomLeft = points.bottomLeft
        filter.bottomRight = points.bottomRight

        guard let outputImage = filter.outputImage,
              let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return normalizedImage
        }

        return UIImage(cgImage: cgImage, scale: normalizedImage.scale, orientation: .up)
    }

    func recognizeText(in image: UIImage) async throws -> OCRResult {
        let normalizedImage = normalizedImage(image)
        let variants = Self.ocrVariants(
            for: normalizedImage,
            enhance: self.enhanceReceiptImage(_:),
            threshold: self.thresholdedReceiptImage(_:),
            upscale: self.upscaledReceiptImage(_:)
        )
        var recognizedLines: [RecognizedLine] = []
        for variant in variants {
            let variantLines = try await Self.recognizedLines(in: variant)
            recognizedLines.append(contentsOf: variantLines)
        }
        let mergedLines = Self.mergeRecognizedLines(recognizedLines)
        let mergedText = mergedLines.map(\.text).joined(separator: "\n")
        return OCRResult(rawText: mergedText, lines: mergedLines)
    }

    private static func ocrVariants(
        for image: UIImage,
        enhance: (UIImage) -> UIImage,
        threshold: (UIImage) -> UIImage,
        upscale: (UIImage) -> UIImage
    ) -> [UIImage] {
        let enhanced = enhance(image)
        let thresholded = threshold(image)
        let thresholdedEnhanced = threshold(enhanced)
        let upscaled = upscale(image)
        let upscaledEnhanced = upscale(enhanced)

        return [image, enhanced, thresholded, thresholdedEnhanced, upscaled, upscaledEnhanced]
    }

    private static func recognizedLines(in image: UIImage) async throws -> [RecognizedLine] {
        if #available(iOS 26.0, *) {
            let documentLines = try await recognizedDocumentLines(in: image)
            if documentLines.isEmpty == false {
                return documentLines
            }
        }

        return try recognizedTextLines(in: image)
    }

    @available(iOS 26.0, *)
    private static func recognizedDocumentLines(in image: UIImage) async throws -> [RecognizedLine] {
        guard let cgImage = image.cgImage else {
            throw OCRServiceError.unsupportedImage
        }

        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.automaticallyDetectLanguage = false
        request.textRecognitionOptions.maximumCandidateCount = 3
        request.textRecognitionOptions.minimumTextHeightFraction = 0.008
        request.textRecognitionOptions.customWords = Self.customReceiptWords
        request.textRecognitionOptions.recognitionLanguages = Self.preferredLanguages.map(Locale.Language.init(identifier:))

        let observations = try await request.perform(on: cgImage, orientation: nil)
        return observations.flatMap { observation in
            observation.document.text.lines.compactMap { line -> RecognizedLine? in
                let text = Self.cleanedOCRText(line.transcript)
                guard text.isEmpty == false else {
                    return nil
                }

                let boundingBox = line.boundingRegion.boundingBox.cgRect
                let score = Self.candidateScore(text, confidence: 0.82)
                return RecognizedLine(
                    text: text,
                    score: score,
                    minX: boundingBox.minX,
                    maxX: boundingBox.maxX,
                    midY: boundingBox.midY
                )
            }
        }
    }

    private static func recognizedTextLines(in image: UIImage) throws -> [RecognizedLine] {
        guard let cgImage = image.cgImage else {
            throw OCRServiceError.unsupportedImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false
        request.recognitionLanguages = Self.preferredLanguages
        request.customWords = Self.customReceiptWords
        request.minimumTextHeight = 0.008

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        return observations.compactMap { observation in
            let candidates = observation.topCandidates(3)
            guard let bestCandidate = Self.bestCandidate(from: candidates) else {
                return nil
            }

            let text = Self.cleanedOCRText(bestCandidate.string)
            guard text.isEmpty == false else { return nil }

            return RecognizedLine(
                text: text,
                score: Self.candidateScore(text, confidence: bestCandidate.confidence),
                minX: observation.boundingBox.minX,
                maxX: observation.boundingBox.maxX,
                midY: observation.boundingBox.midY
            )
        }
    }

    private static func bestCandidate(from candidates: [VNRecognizedText]) -> VNRecognizedText? {
        candidates.max { lhs, rhs in
            Self.candidateScore(lhs.string, confidence: lhs.confidence) < Self.candidateScore(rhs.string, confidence: rhs.confidence)
        }
    }

    private static func candidateScore(_ text: String, confidence: Float) -> Double {
        let lowercased = text.lowercased()
        var score = Double(confidence)

        if lowercased.range(of: #"\d+[.,]\d{2}"#, options: .regularExpression) != nil {
            score += 0.25
        }

        if Self.customReceiptWords.contains(where: lowercased.contains) {
            score += 0.18
        }

        if lowercased.contains("total") || lowercased.contains("subtotal") || lowercased.contains("tax") {
            score += 0.12
        }

        if text.rangeOfCharacter(from: .letters) != nil {
            score += 0.08
        }

        if text.range(of: #"[A-Za-z]{2,}\d+[A-Za-z]{2,}"#, options: .regularExpression) != nil {
            score -= 0.08
        }

        return score
    }

    private static func mergeRecognizedLines(_ lines: [RecognizedLine]) -> [OCRTextLine] {
        let grouped = Dictionary(grouping: lines) { line in
            let yBucket = Int((line.midY * 100).rounded())
            let normalized = Self.normalizeOCRLine(line.text)
            return "\(yBucket)|\(normalized)"
        }

        let merged = grouped.compactMap { _, variants -> RecognizedLine? in
            variants.max { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.text.count < rhs.text.count
                }
                return lhs.score < rhs.score
            }
        }
        .sorted {
            if abs($0.midY - $1.midY) < 0.012 {
                return $0.minX < $1.minX
            }
            return $0.midY > $1.midY
        }

        return merged.reduce(into: [OCRTextLine]()) { result, line in
                let cleaned = Self.cleanedOCRText(line.text)
                guard cleaned.isEmpty == false else { return }
                guard Self.isLikelyUsefulOCRLine(cleaned) else { return }
                if result.last?.text != cleaned {
                    result.append(
                        OCRTextLine(
                            text: cleaned,
                            minX: line.minX,
                            maxX: line.maxX,
                            midY: line.midY
                        )
                    )
                }
            }
    }

    private static func cleanedOCRText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"[\u{00A0}\t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[|]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([.,:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([.,:])\s+"#, with: "$1 ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLikelyUsefulOCRLine(_ line: String) -> Bool {
        let letters = line.filter(\.isLetter).count
        let digits = line.filter(\.isNumber).count
        guard letters + digits > 0 else { return false }
        guard line.count <= 120 else { return false }
        if line.count <= 2, digits == 0 { return false }
        return true
    }

    private static func normalizeOCRLine(_ line: String) -> String {
        line.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func denormalizedPoints(for quadrilateral: ReceiptQuadrilateral, imageSize: CGSize) -> ReceiptQuadrilateral {
        func clamp(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: min(max(point.x, 0.02), 0.98),
                y: min(max(point.y, 0.02), 0.98)
            )
        }

        func convert(_ point: CGPoint) -> CGPoint {
            let clamped = clamp(point)
            return CGPoint(
                x: clamped.x * imageSize.width,
                y: clamped.y * imageSize.height
            )
        }

        return ReceiptQuadrilateral(
            topLeft: convert(quadrilateral.topLeft),
            topRight: convert(quadrilateral.topRight),
            bottomRight: convert(quadrilateral.bottomRight),
            bottomLeft: convert(quadrilateral.bottomLeft)
        )
    }
}

private struct RecognizedLine {
    let text: String
    let score: Double
    let minX: CGFloat
    let maxX: CGFloat
    let midY: CGFloat
}

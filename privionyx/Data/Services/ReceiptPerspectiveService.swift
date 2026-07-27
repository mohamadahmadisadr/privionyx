import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import UIKit
import Vision

nonisolated struct ReceiptPerspectiveService {
    private let context = ReceiptImageProcessor.sharedContext
    private let imageProcessor: ReceiptImageProcessor

    init(imageProcessor: ReceiptImageProcessor = ReceiptImageProcessor()) {
        self.imageProcessor = imageProcessor
    }

    func detectReceiptQuadrilateral(in image: UIImage) async -> ReceiptQuadrilateral? {
        let normalizedImage = imageProcessor.normalizedImage(image)

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
        let normalizedImage = imageProcessor.normalizedImage(image)

        // A quadrilateral that is already the whole frame has nothing to correct, and running
        // the filter anyway is not free: the perspective resample softens every glyph it
        // touches. An IKEA receipt lost four rows and its total that way, to a "crop" that
        // changed no boundary at all.
        guard Self.isFullFrame(quadrilateral) == false else {
            return normalizedImage
        }

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

    /// Whether the quadrilateral is the whole frame, to within a rounding of the corner
    /// handles. Deliberately generous: a crop that would trim half a percent off an edge is
    /// not worth a full-image resample either.
    private static func isFullFrame(_ quadrilateral: ReceiptQuadrilateral) -> Bool {
        let slack = 0.005
        return quadrilateral.topLeft.x <= slack && quadrilateral.topLeft.y >= 1 - slack
            && quadrilateral.topRight.x >= 1 - slack && quadrilateral.topRight.y >= 1 - slack
            && quadrilateral.bottomRight.x >= 1 - slack && quadrilateral.bottomRight.y <= slack
            && quadrilateral.bottomLeft.x <= slack && quadrilateral.bottomLeft.y <= slack
    }

    private func denormalizedPoints(for quadrilateral: ReceiptQuadrilateral, imageSize: CGSize) -> ReceiptQuadrilateral {
        // Clamped to the frame and no further. The old 0.02 inset shaved a further 2% off
        // every side of an already-chosen crop, which on a receipt photographed edge to edge
        // is a column of digits.
        func clamp(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: min(max(point.x, 0), 1),
                y: min(max(point.y, 0), 1)
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

extension ReceiptPerspectiveService: ReceiptPerspectiveCorrecting {}

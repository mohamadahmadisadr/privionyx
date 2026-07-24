import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import UIKit
import Vision

struct ReceiptPerspectiveService {
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

extension ReceiptPerspectiveService: ReceiptPerspectiveCorrecting {}

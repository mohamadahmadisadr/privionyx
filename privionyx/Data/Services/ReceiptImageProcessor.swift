import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import UIKit

struct ReceiptImageProcessor {
    private let context = CIContext(options: nil)

    func normalizedImage(_ image: UIImage) -> UIImage {
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = image.scale
        rendererFormat.opaque = true

        let bounds = CGRect(origin: .zero, size: image.size)
        let renderer = UIGraphicsImageRenderer(size: image.size, format: rendererFormat)
        return renderer.image { context in
            // Receipts are dark ink on light paper, so transparency has to be flattened onto
            // white. Drawing onto the default backing composites transparent pixels to black,
            // which turns an alpha-channel PNG into black-on-black — Vision reads that as a
            // blank page and returns no text at all.
            UIColor.white.setFill()
            context.fill(bounds)
            image.draw(in: bounds)
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
}

extension ReceiptImageProcessor: ReceiptImageProcessing {}

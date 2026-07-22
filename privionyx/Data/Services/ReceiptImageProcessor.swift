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

    /// Longest edge, in pixels, that recognition is given.
    ///
    /// Recognition cares about how tall the text is, not how many pixels surround it. Receipt
    /// rows in the corpus run about 1.5% of image height, so at this cap they are still ~45px
    /// — far above the 0.8% floor the requests are configured with — while a 24 MP capture
    /// costs about a fifth as much to process.
    static let recognitionPixelCap: CGFloat = 3000

    /// Scales a capture down to something recognition can afford.
    ///
    /// A modern iPhone photo is around 24 megapixels, or 96 MB as a bitmap, and the pipeline
    /// touches several copies of it — decode, redraw, CGImage, plus whatever Vision allocates.
    /// Measured end to end that peaked at 532 MB for a single receipt, which is a jetsam risk
    /// on a smaller device and pointless when the extra pixels buy no accuracy.
    func downscaledForRecognition(_ image: UIImage) -> UIImage {
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let longestEdge = max(pixelSize.width, pixelSize.height)
        guard longestEdge > Self.recognitionPixelCap else { return image }

        let scale = Self.recognitionPixelCap / longestEdge
        let target = CGSize(
            width: (pixelSize.width * scale).rounded(),
            height: (pixelSize.height * scale).rounded()
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
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

}

extension ReceiptImageProcessor: ReceiptImageProcessing {}

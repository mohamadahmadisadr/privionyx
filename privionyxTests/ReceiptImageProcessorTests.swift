import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import privionyx

/// `normalizedImage` now returns its input untouched when a redraw would change nothing,
/// which is what makes the pipeline's defensive calls free. These pin both halves: the cases
/// it must still redraw, and the case it must skip.
@Suite("Receipt image processing")
struct ReceiptImageProcessorTests {
    private let processor = ReceiptImageProcessor()

    @Test("Transparent pixels are flattened onto white")
    func flattensTransparency() throws {
        // The bug this exists for: drawing an alpha image onto the default backing
        // composites it to black, and Vision reads a black page as blank.
        let transparent = Self.makeImage(size: CGSize(width: 8, height: 8), opaque: false, fill: .clear)

        let flattened = processor.normalizedImage(transparent)
        let pixel = try #require(Self.firstPixel(of: flattened))

        #expect(pixel.red == 255 && pixel.green == 255 && pixel.blue == 255, "expected white, got \(pixel)")
        #expect(pixel.alpha == 255)
    }

    @Test("An already-flattened, upright image is returned untouched")
    func opaqueImageIsNotRedrawn() {
        let opaque = Self.makeImage(size: CGSize(width: 8, height: 8), opaque: true, fill: .red)

        // Identity, not just equality: a redraw here would allocate a second full-size
        // bitmap to produce the same pixels, which is the waste being removed.
        #expect(processor.normalizedImage(opaque) === opaque)
    }

    @Test("A rotated image is redrawn even when opaque")
    func rotatedImageIsBakedUpright() throws {
        let upright = Self.makeImage(size: CGSize(width: 8, height: 4), opaque: true, fill: .red)
        let rotated = UIImage(cgImage: try #require(upright.cgImage), scale: 1, orientation: .right)

        let normalized = processor.normalizedImage(rotated)

        // Vision is handed image.cgImage directly, which ignores the orientation flag, so
        // the rotation has to be baked in or the page is recognised sideways.
        #expect(normalized !== rotated)
        #expect(normalized.imageOrientation == .up)
        #expect(normalized.size == CGSize(width: 4, height: 8), "the rotation was not applied")
    }

    @Test("Preparing for recognition caps the longest edge")
    func recognitionDownscalesLargeCaptures() {
        let cap = ReceiptImageProcessor.recognitionPixelCap
        let oversized = Self.makeImage(size: CGSize(width: cap * 2, height: cap), opaque: true, fill: .red)

        let prepared = processor.preparedForRecognition(oversized)
        let pixelSize = CGSize(
            width: prepared.size.width * prepared.scale,
            height: prepared.size.height * prepared.scale
        )

        #expect(max(pixelSize.width, pixelSize.height) == cap)
        // Aspect ratio preserved.
        #expect(abs(pixelSize.width / pixelSize.height - 2) < 0.01)
    }

    @Test("Preparing for recognition flattens as it downscales")
    func recognitionFlattensWhileDownscaling() throws {
        let cap = ReceiptImageProcessor.recognitionPixelCap
        let oversized = Self.makeImage(size: CGSize(width: cap * 2, height: cap), opaque: false, fill: .clear)

        // One redraw does both. Previously this was a downscale followed by a separate
        // flatten, the second of which copied the first unchanged.
        let prepared = processor.preparedForRecognition(oversized)
        let pixel = try #require(Self.firstPixel(of: prepared))

        #expect(pixel.red == 255 && pixel.green == 255 && pixel.blue == 255)
        #expect(prepared.imageOrientation == .up)
    }

    @Test("An image already within the cap is not scaled up")
    func smallImageKeepsItsSize() {
        let small = Self.makeImage(size: CGSize(width: 200, height: 100), opaque: true, fill: .red)

        let prepared = processor.preparedForRecognition(small)

        #expect(prepared.size == small.size)
        #expect(prepared === small, "an opaque image inside the cap needs no redraw at all")
    }

    // MARK: - Helpers

    private static func makeImage(size: CGSize, opaque: Bool, fill: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = opaque

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            fill.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private struct Pixel: CustomStringConvertible {
        let red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8
        var description: String { "rgba(\(red), \(green), \(blue), \(alpha))" }
    }

    /// Samples the top-left pixel by drawing into a known 1×1 RGBA buffer, so the result
    /// doesn't depend on the source's own colour space or alpha layout.
    private static func firstPixel(of image: UIImage) -> Pixel? {
        guard let cgImage = image.cgImage else { return nil }

        var bytes = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &bytes,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Pixel(red: bytes[0], green: bytes[1], blue: bytes[2], alpha: bytes[3])
    }
}

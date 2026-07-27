import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// The app icon, as the code that draws it.
//
//   swift Tools/MakeAppIcon.swift privionyx/Assets.xcassets/AppIcon.appiconset
//
// Kept in the repository so the icon stays editable: a nudged margin or a re-tuned accent
// is a diff here, rather than an opaque binary nobody can open. Renders the three
// 1024×1024 variants iOS 18+ expects — the full-colour icon, a dark variant on
// transparency (the system supplies its own backdrop), and a grayscale tinted variant the
// system maps onto the user's chosen tint.
//
// The mark is a receipt under a scan beam: what the app does, in the two shapes that
// survive being 40 points wide.

let size: CGFloat = 1024

enum Variant {
    case light, dark, tinted
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func gray(_ level: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: level, green: level, blue: level, alpha: alpha)
}

/// A receipt: rounded at the top, torn along the bottom.
func receiptPath(x0: CGFloat, x1: CGFloat, top: CGFloat, bodyBottom: CGFloat, teeth: Int, depth: CGFloat, radius r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: x0, y: bodyBottom))
    path.addLine(to: CGPoint(x: x0, y: top + r))
    path.addArc(tangent1End: CGPoint(x: x0, y: top), tangent2End: CGPoint(x: x0 + r, y: top), radius: r)
    path.addLine(to: CGPoint(x: x1 - r, y: top))
    path.addArc(tangent1End: CGPoint(x: x1, y: top), tangent2End: CGPoint(x: x1, y: top + r), radius: r)
    path.addLine(to: CGPoint(x: x1, y: bodyBottom))

    let toothWidth = (x1 - x0) / CGFloat(teeth)
    for tooth in 0..<teeth {
        path.addLine(to: CGPoint(x: x1 - (CGFloat(tooth) + 0.5) * toothWidth, y: bodyBottom + depth))
        path.addLine(to: CGPoint(x: x1 - CGFloat(tooth + 1) * toothWidth, y: bodyBottom))
    }

    path.closeSubpath()
    return path
}

func bar(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: width, height: height), cornerWidth: height / 2, cornerHeight: height / 2, transform: nil)
}

func fill(_ ctx: CGContext, _ path: CGPath, _ color: CGColor) {
    ctx.saveGState()
    ctx.setFillColor(color)
    ctx.addPath(path)
    ctx.fillPath()
    ctx.restoreGState()
}

func fillGradient(_ ctx: CGContext, _ path: CGPath, colors: [CGColor], from: CGPoint, to: CGPoint) {
    guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: nil) else { return }
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func render(_ variant: Variant) -> CGImage {
    let ctx = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    // Draw with y running downwards, which is how the layout below is measured.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setShouldAntialias(true)

    // MARK: Background
    //
    // Only the light variant carries one: iOS composites the dark and tinted variants over
    // backgrounds of its own, and painting our own would show as a square inside the mask.
    if variant == .light {
        fillGradient(
            ctx,
            CGPath(rect: CGRect(x: 0, y: 0, width: size, height: size), transform: nil),
            colors: [rgb(0x232752), rgb(0x14152C), rgb(0x0A0B14)],
            from: CGPoint(x: 0, y: 0),
            to: CGPoint(x: size, y: size)
        )

        // A glow behind the receipt, so the paper sits in light rather than on a flat field.
        if let glow = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: [rgb(0x6C5CFF, 0.55), rgb(0x6C5CFF, 0)] as CFArray,
            locations: [0, 1]
        ) {
            ctx.saveGState()
            ctx.drawRadialGradient(
                glow,
                startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
                endCenter: CGPoint(x: 512, y: 470), endRadius: 470,
                options: []
            )
            ctx.restoreGState()
        }
    }

    // The artwork below is laid out on a 1024 grid, then scaled up about the centre so the
    // receipt fills the icon the way iOS expects rather than floating in its margins.
    ctx.translateBy(x: 512, y: 512)
    ctx.scaleBy(x: 1.1, y: 1.1)
    ctx.translateBy(x: -512, y: -512)

    // MARK: Receipt
    let x0: CGFloat = 286, x1: CGFloat = 738
    let top: CGFloat = 250, bodyBottom: CGFloat = 730
    let paper = receiptPath(x0: x0, x1: x1, top: top, bodyBottom: bodyBottom, teeth: 7, depth: 44, radius: 40)

    // Paper: white on the coloured background, but knocked back for the dark variant, where
    // the system's near-black backdrop would otherwise turn a full-white slab into a lamp.
    let paperColor: CGColor
    switch variant {
    case .light: paperColor = rgb(0xFFFFFF)
    case .dark: paperColor = rgb(0xE4E9F4)
    case .tinted: paperColor = gray(0.96)
    }

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 46, color: rgb(0x05060E, variant == .light ? 0.55 : 0.35))
    fill(ctx, paper, paperColor)
    ctx.restoreGState()

    // MARK: Printed content
    let inset: CGFloat = 58
    let contentLeft = x0 + inset
    let contentRight = x1 - inset
    let contentWidth = contentRight - contentLeft

    let headline = variant == .tinted ? gray(0.30) : rgb(0x2B3040)
    // A shade darker on the dimmed dark-variant paper, to hold the same contrast.
    let bodyLine: CGColor
    switch variant {
    case .light: bodyLine = rgb(0xC9CFDB)
    case .dark: bodyLine = rgb(0xAEB6C8)
    case .tinted: bodyLine = gray(0.62)
    }

    fill(ctx, bar(contentLeft, 306, 206, 32), headline)
    fill(ctx, bar(contentLeft, 384, contentWidth, 20), bodyLine)
    fill(ctx, bar(contentLeft, 424, 250, 20), bodyLine)

    // Torn-off dashed rule above the total, the detail that says "receipt" and not "note".
    ctx.saveGState()
    ctx.setStrokeColor(variant == .tinted ? gray(0.72) : rgb(0xD9DFE9))
    ctx.setLineWidth(8)
    ctx.setLineCap(.butt)
    ctx.setLineDash(phase: 0, lengths: [22, 18])
    ctx.move(to: CGPoint(x: contentLeft, y: 566))
    ctx.addLine(to: CGPoint(x: contentRight, y: 566))
    ctx.strokePath()
    ctx.restoreGState()

    // The total: the one figure the app exists to get right, so it gets the accent.
    fill(ctx, bar(contentLeft, 621, 124, 26), variant == .tinted ? gray(0.62) : rgb(0xAFB6C4))

    let totalBar = bar(contentRight - 182, 611, 182, 46)
    if variant == .tinted {
        fill(ctx, totalBar, gray(0.18))
    } else {
        fillGradient(
            ctx,
            totalBar,
            colors: [rgb(0x7C6BFF), rgb(0x5B8CFF)],
            from: CGPoint(x: contentRight - 182, y: 611),
            to: CGPoint(x: contentRight, y: 657)
        )
    }

    // MARK: Scan beam
    //
    // Overhangs both edges of the paper — that overhang is what reads as a scanner sweeping
    // the receipt rather than as one more printed line.
    let beamRect = CGRect(x: 206, y: 489, width: size - 412, height: 24)
    let beam = CGPath(roundedRect: beamRect, cornerWidth: 11, cornerHeight: 11, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 44, color: variant == .tinted ? gray(1, 0.5) : rgb(0x7AA8FF, 0.9))
    if variant == .tinted {
        fill(ctx, beam, gray(1))
    } else {
        fillGradient(
            ctx,
            beam,
            colors: [rgb(0x6C5CFF), rgb(0x63C7FF)],
            from: CGPoint(x: beamRect.minX, y: 0),
            to: CGPoint(x: beamRect.maxX, y: 0)
        )
    }
    ctx.restoreGState()

    // A hot core down the middle of the beam, so it stays a beam once it is 40 points wide.
    fill(ctx, CGPath(roundedRect: CGRect(x: 226, y: 497, width: size - 452, height: 8), cornerWidth: 4, cornerHeight: 4, transform: nil), gray(1, 0.92))

    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("could not create \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(url.path)") }
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
write(render(.light), to: output.appendingPathComponent("AppIcon.png"))
write(render(.dark), to: output.appendingPathComponent("AppIcon-Dark.png"))
write(render(.tinted), to: output.appendingPathComponent("AppIcon-Tinted.png"))
print("wrote 3 icons to \(output.path)")

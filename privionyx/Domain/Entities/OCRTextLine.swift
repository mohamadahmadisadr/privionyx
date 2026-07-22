import CoreGraphics
import Foundation

/// One assembled visual row of a receipt.
///
/// Vision emits a receipt's label column and amount column as separate observations —
/// "SUBTOTAL" and "228.02" are never returned as one result. A row here is those
/// fragments joined back together in reading order, so `text` carries the label and its
/// value the way the receipt prints them.
struct OCRTextLine: Hashable {
    let text: String
    let minX: CGFloat
    let maxX: CGFloat
    let midY: CGFloat
    /// Row height in normalized image coordinates. Row clustering scales its tolerance to
    /// this rather than to a fixed constant, which is what lets one implementation handle
    /// both a 500px template and a 5712px camera capture.
    let height: CGFloat

    init(text: String, minX: CGFloat, maxX: CGFloat, midY: CGFloat, height: CGFloat = 0) {
        self.text = text
        self.minX = minX
        self.maxX = maxX
        self.midY = midY
        self.height = height
    }
}

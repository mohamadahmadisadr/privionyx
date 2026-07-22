import CoreGraphics
import Foundation

struct OCRTextLine: Hashable {
    let text: String
    let minX: CGFloat
    let maxX: CGFloat
    let midY: CGFloat
}

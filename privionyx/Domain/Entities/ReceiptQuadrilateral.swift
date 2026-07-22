import CoreGraphics
import Foundation

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

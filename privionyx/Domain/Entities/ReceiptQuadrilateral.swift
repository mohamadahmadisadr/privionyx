import CoreGraphics
import Foundation

nonisolated struct ReceiptQuadrilateral: Hashable, Sendable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    /// The whole frame, because this is what gets used when rectangle detection finds
    /// nothing — and a guessed inset is not a neutral starting point. Insetting by 8% used
    /// to throw away the outer eighth of every side of a receipt that already filled the
    /// frame, which is where "SUPERMARKET" came back as "SUPERMARKE" and a Costco
    /// letterhead came back as "WHOLESALE". When the app cannot tell where the paper is,
    /// keeping every pixel is the only safe answer; the crop editor still lets the user
    /// pull the corners in.
    static let `default` = ReceiptQuadrilateral(
        topLeft: CGPoint(x: 0, y: 1),
        topRight: CGPoint(x: 1, y: 1),
        bottomRight: CGPoint(x: 1, y: 0),
        bottomLeft: CGPoint(x: 0, y: 0)
    )
}

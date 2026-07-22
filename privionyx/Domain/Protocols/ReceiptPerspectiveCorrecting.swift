import UIKit

protocol ReceiptPerspectiveCorrecting: Sendable {
    func detectReceiptQuadrilateral(in image: UIImage) async -> ReceiptQuadrilateral?
    func cropReceiptImage(_ image: UIImage, quadrilateral: ReceiptQuadrilateral) -> UIImage
}

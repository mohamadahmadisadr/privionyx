import UIKit

protocol ReceiptImageProcessing: Sendable {
    func normalizedImage(_ image: UIImage) -> UIImage
    func enhanceReceiptImage(_ image: UIImage) -> UIImage
}

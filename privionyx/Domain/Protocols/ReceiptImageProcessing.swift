import UIKit

nonisolated protocol ReceiptImageProcessing: Sendable {
    func normalizedImage(_ image: UIImage) -> UIImage
    func enhanceReceiptImage(_ image: UIImage) -> UIImage
    func preparedForRecognition(_ image: UIImage) -> UIImage
}

import UIKit

protocol OCRService: Sendable {
    func recognizeText(in image: UIImage) async throws -> OCRResult
}

import Foundation

protocol ReceiptMLExtractor: Sendable {
    func extract(from lines: [OCRTextLine]) -> ReceiptMLExtraction?
}

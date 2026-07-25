import Foundation

nonisolated protocol ReceiptMLExtractor: Sendable {
    func extract(from lines: [OCRTextLine]) -> ReceiptMLExtraction?
}

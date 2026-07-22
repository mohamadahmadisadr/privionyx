import Foundation

protocol ReceiptParser: Sendable {
    func parse(rawText: String) async -> ParsedReceiptData
    func parse(ocrResult: OCRResult) async -> ParsedReceiptData
}

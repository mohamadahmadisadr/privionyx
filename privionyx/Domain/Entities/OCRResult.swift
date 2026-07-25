import Foundation

nonisolated struct OCRResult: Sendable {
    let rawText: String
    let lines: [OCRTextLine]
}

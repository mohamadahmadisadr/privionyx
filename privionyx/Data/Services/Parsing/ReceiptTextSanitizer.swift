import Foundation

struct ReceiptTextSanitizer {
    func normalizedTokenLine(_ line: String) -> String {
        line.lowercased()
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cleanedReceiptLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"[\u{00A0}\t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\d)[oO](?=\d)"#, with: "0", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\d)[lI](?=\d)"#, with: "1", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\$)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

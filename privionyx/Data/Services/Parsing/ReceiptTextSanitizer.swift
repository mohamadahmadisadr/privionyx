import Foundation

struct ReceiptTextSanitizer {
    /// Flattens a line's punctuation so labels compare equal — "sub-total", "sub.total" and
    /// "subtotal" all become the same token.
    ///
    /// A decimal point *between digits* is left alone. Callers match labels against this
    /// string and then read the amount out of it, and blanking every dot turned
    /// "subtotal 1,998.00" into "subtotal 1,998 00" — where the amount pattern backtracks
    /// past the orphaned "998" and matches "1,99". With ordinary amounts the capture simply
    /// failed and a fallback covered for it, so this only surfaced once a receipt carried a
    /// thousands separator, and then it produced a confident wrong figure rather than none.
    func normalizedTokenLine(_ line: String) -> String {
        line.lowercased()
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"(?<!\d)\.|\.(?!\d)"#, with: " ", options: .regularExpression)
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

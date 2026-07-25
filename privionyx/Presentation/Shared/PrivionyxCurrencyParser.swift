import Foundation

/// Reads a currency amount a person typed. The mirror of `PrivionyxCurrencyFormatter`,
/// which writes one.
///
/// Deliberately separate from `AmountExtractor`'s parsing, which reads figures off a
/// receipt: that one works on OCR output and can lean on surrounding layout, while this one
/// has to accept whatever someone types into a text field — a leading currency symbol,
/// thousands separators, or a comma used as the decimal mark.
enum PrivionyxCurrencyParser {
    /// The amount `text` denotes, or nil when it doesn't denote one.
    ///
    /// Separator handling is by position rather than by locale, because a text field can
    /// receive either convention regardless of the device's region — someone pasting a
    /// figure from a European invoice into a phone set to Canada is not a mistake to reject.
    static func amount(from text: String) -> Double? {
        var value = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[^0-9,.\-]"#, with: "", options: .regularExpression)

        // A lone separator or sign is someone mid-keystroke, not a value.
        guard value.isEmpty == false, value != "-", value != ".", value != "," else {
            return nil
        }

        if value.contains(","), value.contains(".") {
            // Both present: whichever comes last is the decimal mark, and the other is
            // grouping. "1.234,56" and "1,234.56" are the same number written two ways.
            let commaIndex = value.lastIndex(of: ",") ?? value.startIndex
            let dotIndex = value.lastIndex(of: ".") ?? value.startIndex
            if commaIndex > dotIndex {
                value = value.replacingOccurrences(of: ".", with: "")
                value = value.replacingOccurrences(of: ",", with: ".")
            } else {
                value = value.replacingOccurrences(of: ",", with: "")
            }
        } else if let commaIndex = value.lastIndex(of: ",") {
            // Only commas: exactly two digits after the last one reads as a decimal mark
            // ("12,50"), anything else as grouping ("1,234").
            let decimalDigits = value.distance(from: value.index(after: commaIndex), to: value.endIndex)
            value = decimalDigits == 2
                ? value.replacingOccurrences(of: ",", with: ".")
                : value.replacingOccurrences(of: ",", with: "")
        }

        return Double(value)
    }
}

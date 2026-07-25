import Foundation

nonisolated struct ReceiptTextSanitizer {
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

    /// Punctuation that can appear inside a printed figure without making it something other
    /// than a figure — amounts, dates, times, percentages, reference numbers.
    private static let numericPunctuation: Set<Character> = [
        ".", ",", ":", "/", "-", "+", "$", "%", "#", "*", "(", ")"
    ]

    /// Repairs letters a worn print head leaves where digits belong: `O` for zero, `l` and `I`
    /// for one.
    ///
    /// The between-digits rule alone was too narrow. Faded thermal print puts the damage at the
    /// edge of a number as often as in the middle — `7.5O`, `15.5O`, `2.O2` — and there the
    /// lookbehind saw a period and declined, so a subtotal and a tax line both came back `nil`.
    /// `DateExtractor` had already needed the same thing for `03/1O/2026` and `O8:45` and grew
    /// its own pair of edge rules; the repair lives here now so both paths share one definition.
    ///
    /// Widening it by word boundary alone would have been wrong: a boundary fires against a
    /// space as readily as against a decimal point, so `H2O` would have become `H20`. What
    /// separates `7.5O` from `H2O` is not the character beside the letter but the token around
    /// it — one is otherwise entirely numeric and the other is a name that happens to contain a
    /// digit. So the edge repair asks that of the whole token, and a token carrying any other
    /// letter is left alone. That is also why the between-digits rules stay: they run over the
    /// line and still reach a `1O2` buried inside `REF#1O2`.
    ///
    /// A token with no digit at all is never repaired, which keeps `O.OO` unrecovered but keeps
    /// separator rules, currency codes and ordinary words safe. That trade is deliberate — a
    /// figure with no surviving digit has nothing left to confirm it was a figure.
    func repairedDigitGlyphs(_ line: String) -> String {
        let betweenDigits = line
            .replacingOccurrences(of: #"(?<=\d)[oO](?=\d)"#, with: "0", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\d)[lI](?=\d)"#, with: "1", options: .regularExpression)

        var repaired = ""
        repaired.reserveCapacity(betweenDigits.count)
        var token = ""
        for character in betweenDigits {
            if character.isWhitespace {
                repaired += Self.repairedNumericToken(token)
                repaired.append(character)
                token = ""
            } else {
                token.append(character)
            }
        }
        return repaired + Self.repairedNumericToken(token)
    }

    /// Returns `token` with damaged glyphs restored, or unchanged if it isn't a printed figure.
    private static func repairedNumericToken(_ token: String) -> String {
        var sawDigit = false
        var repaired = ""
        repaired.reserveCapacity(token.count)

        for character in token {
            if character.isASCII, character.isNumber {
                sawDigit = true
                repaired.append(character)
            } else if character == "o" || character == "O" {
                repaired.append("0")
            } else if character == "l" || character == "I" {
                repaired.append("1")
            } else if numericPunctuation.contains(character) {
                repaired.append(character)
            } else {
                return token
            }
        }

        return sawDigit ? repaired : token
    }

    func cleanedReceiptLine(_ line: String) -> String {
        repairedDigitGlyphs(
            line.replacingOccurrences(of: #"[\u{00A0}\t]+"#, with: " ", options: .regularExpression)
        )
        .replacingOccurrences(of: #"(?<=\$)\s+"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

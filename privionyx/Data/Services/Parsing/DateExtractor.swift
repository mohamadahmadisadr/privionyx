import Foundation

struct DateExtractor {
    func extractDate(from lines: [String]) -> Date? {
        let patterns = [
            "MM/dd/yyyy", "MM/dd/yy", "yyyy-MM-dd", "dd/MM/yyyy", "dd/MM/yy",
            "MM-dd-yyyy", "MM-dd-yy", "dd-MM-yyyy", "dd-MM-yy",
            "MMM d yyyy", "MMMM d yyyy", "d MMM yyyy", "d MMMM yyyy"
        ]
        let formatter = makePOSIXFormatter()

        for line in lines {
            let sanitizedLine = line
                .replacingOccurrences(of: #"(?i)\b(o|O)(?=\d)"#, with: "0", options: .regularExpression)
                .replacingOccurrences(of: #"(?<=\d)(o|O)\b"#, with: "0", options: .regularExpression)
                .replacingOccurrences(of: ",", with: " ")
            let slashCandidates = sanitizedLine.split(whereSeparator: \.isWhitespace)

            for candidate in slashCandidates {
                for pattern in patterns {
                    formatter.dateFormat = pattern
                    if let date = formatter.date(from: String(candidate)) {
                        return date
                    }
                }
            }

            let joinedCandidates = candidateDateSegments(from: sanitizedLine)
            for candidate in joinedCandidates {
                for pattern in patterns {
                    formatter.dateFormat = pattern
                    if let date = formatter.date(from: candidate) {
                        return date
                    }
                }
            }
        }

        return nil
    }

    private func candidateDateSegments(from line: String) -> [String] {
        let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count >= 3 else { return [] }

        var segments: [String] = []

        for index in 0..<(words.count - 2) {
            segments.append(words[index...min(index + 2, words.count - 1)].joined(separator: " "))
        }

        return segments
    }

    private func makePOSIXFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }
}

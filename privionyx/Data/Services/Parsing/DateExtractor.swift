import Foundation

struct DateExtractor {
    /// Labels marking a date that is not the transaction's own. On an LCBO receipt the
    /// return-by date is printed lower and larger than the purchase timestamp, and a plain
    /// top-down scan reaches it first.
    private static let futureDateMarkers = [
        "return", "retour", "valid", "valide", "limite", "expir",
        "warranty", "garantie", "best before", "use by"
    ]

    /// A time beside a date is the strongest available signal that it is the moment of
    /// purchase rather than a deadline printed near it.
    private static let timePattern = #"\d{1,2}:\d{2}"#

    func extractDate(from lines: [String]) -> Date? {
        // Any date accompanied by a clock time wins outright, whatever its position.
        if let stamped = firstDate(in: lines, restrictedToLinesWithTime: true) {
            return stamped
        }
        return firstDate(in: lines, restrictedToLinesWithTime: false)
    }

    private func firstDate(in lines: [String], restrictedToLinesWithTime: Bool) -> Date? {
        let usable = lines.enumerated().filter { index, line in
            if restrictedToLinesWithTime,
               line.range(of: Self.timePattern, options: .regularExpression) == nil {
                return false
            }
            // A clock time settles it on its own: deadlines are printed as bare dates. The
            // LCBO receipt puts "Date limite pour retour" two rows above its purchase
            // timestamp, so applying the deadline check here discarded the right answer
            // along with the wrong one.
            if restrictedToLinesWithTime { return true }

            // Without a time, fall back to context — a deadline's label often sits a row or
            // two above the date it introduces, so the neighbourhood is checked.
            let context = lines[max(0, index - 2)...index].joined(separator: " ").lowercased()
            return Self.futureDateMarkers.contains(where: context.contains) == false
        }
        .map(\.element)

        return scanForDate(in: usable)
    }

    private func scanForDate(in lines: [String]) -> Date? {
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
                    if let date = formatter.date(from: String(candidate)), isPlausible(date) {
                        return date
                    }
                }
            }

            let joinedCandidates = candidateDateSegments(from: sanitizedLine)
            for candidate in joinedCandidates {
                for pattern in patterns {
                    formatter.dateFormat = pattern
                    if let date = formatter.date(from: candidate), isPlausible(date) {
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
        // Lenient parsing reads "9/16/23" against "MM/dd/yyyy" as the year 23 AD rather
        // than rejecting it, and that pattern is tried first.
        formatter.isLenient = false
        return formatter
    }

    /// A receipt is a record of a purchase that already happened, on paper that has not
    /// been around for decades. Anything outside that window is a misparse, not a date.
    private func isPlausible(_ date: Date) -> Bool {
        let now = Date.now
        guard let earliest = Calendar.current.date(byAdding: .year, value: -30, to: now),
              let latest = Calendar.current.date(byAdding: .day, value: 2, to: now) else {
            return true
        }
        return date >= earliest && date <= latest
    }
}

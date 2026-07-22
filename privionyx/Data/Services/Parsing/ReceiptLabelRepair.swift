import Foundation

/// Repairs structural labels that recognition got almost right.
///
/// An LCBO receipt in the corpus returned `lotal 33.25` — one glyph wrong in "Total". The
/// text is otherwise perfect, but every rule that keys on the word "total" is exact-match,
/// so the totals block was never located: the total row became a line item, no total was
/// found by label, and a version string in the footer won the fallback instead. A single
/// character cost the receipt its total, its date and its item list.
///
/// Recognition is very good and getting better; what breaks is code that demands it be
/// perfect. Repairing near-misses against a small vocabulary at the point rows are
/// assembled means every matcher downstream sees the intended word without any of them
/// having to know about OCR noise.
enum ReceiptLabelRepair {
    /// Only words that decide document structure. Merchant names and product names are
    /// deliberately absent — correcting those would be inventing content rather than
    /// recovering it, and a wrong guess there is worse than the raw text.
    /// Words one edit apart must both appear here or the repair will rewrite one into the
    /// other: "charge" and "change" differ by a single letter, and correcting a restaurant's
    /// "Service Charge" into "Service Change" moved it from the totals boundary to the
    /// payment-row exclusion, silently adding a fee to the item list.
    private static let vocabulary = [
        "total", "subtotal", "amount", "balance", "payment",
        "deposit", "purchase", "charge", "change", "gratuity"
    ]

    /// Short words are excluded: at four characters or fewer, an edit distance of one
    /// reaches too many unrelated words to be safe ("tax" would swallow "tab" and "max").
    private static let minimumLength = 5

    static func repaired(_ text: String) -> String {
        text
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { word -> Substring in
                guard let replacement = correction(for: word) else { return word }
                return Substring(replacement)
            }
            .joined(separator: " ")
    }

    private static func correction(for word: Substring) -> String? {
        // Compare on letters alone so trailing punctuation and colons do not count as edits,
        // and put the original's casing back afterwards.
        let letters = word.filter(\.isLetter).lowercased()
        guard letters.count >= minimumLength else { return nil }
        guard vocabulary.contains(letters) == false else { return nil }

        guard let match = vocabulary.first(where: { candidate in
            candidate.count >= minimumLength
                && abs(candidate.count - letters.count) <= 1
                && isWithinOneEdit(letters, candidate)
        }) else { return nil }

        let isUppercased = word.filter(\.isLetter).allSatisfy(\.isUppercase)
        let corrected = isUppercased ? match.uppercased() : match
        return word.replacingOccurrences(
            of: word.filter(\.isLetter),
            with: corrected
        )
    }

    /// True when one substitution, insertion or deletion turns `lhs` into `rhs`. A full
    /// Levenshtein matrix is unnecessary for a bounded distance of one.
    private static func isWithinOneEdit(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }

        let a = Array(lhs)
        let b = Array(rhs)

        if a.count == b.count {
            var differences = 0
            for index in a.indices where a[index] != b[index] {
                differences += 1
                if differences > 1 { return false }
            }
            return differences == 1
        }

        // Differing by one character: the longer must contain the shorter with one skip.
        let (shorter, longer) = a.count < b.count ? (a, b) : (b, a)
        guard longer.count - shorter.count == 1 else { return false }

        var shortIndex = 0
        var skipped = false
        for longIndex in longer.indices {
            if shortIndex < shorter.count, shorter[shortIndex] == longer[longIndex] {
                shortIndex += 1
            } else if skipped {
                return false
            } else {
                skipped = true
            }
        }
        return true
    }
}

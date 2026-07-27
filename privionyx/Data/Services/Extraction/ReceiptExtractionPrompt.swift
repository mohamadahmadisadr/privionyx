import Foundation

/// The prompt both language-model engines are given, and the reader for what comes back.
///
/// Shared so the two engines are asked the same question in the same words. When Gemma and
/// Apple Intelligence disagree it should be because the models differ, not because one was
/// handed a better-worded prompt than the other.
nonisolated enum ReceiptExtractionPrompt {
    /// Rows beyond this are dropped. The tail of a receipt is card-network boilerplate and
    /// return policy — never the totals — and both runtimes have a context budget that a
    /// long till roll can exhaust.
    static let maximumRows = 80

    static let instructions = """
    You read shop receipts. You are given the lines of one receipt in the order they are \
    printed, exactly as optical character recognition returned them, including its mistakes.

    Report only what the receipt itself states. Rules that matter more than they look:
    - The total is what the customer actually paid for the goods. It is NOT the cash they \
    handed over, NOT the change, NOT a card pre-authorisation, and NOT a discount or \
    savings line, even when that line begins with the word "Total".
    - The subtotal is the figure before tax. If tax is described as included in the price, \
    the receipt has no separate subtotal to report.
    - The merchant is the shop, taken from the letterhead. It is not the payment network \
    (VISA, MASTERCARD, INTERAC), not a slogan or tagline printed under the name, and not \
    the street address.
    - The date is the transaction's own date, not a "best before", not a return-by deadline, \
    and not a card expiry.
    - Recognition drops and mangles characters. If a field is not legible, leave it out \
    rather than guessing — an omitted field is corrected cheaply, an invented one is not.
    """

    static func prompt(rows: [String], currencyCode: String) -> String {
        let body = rows.prefix(maximumRows).enumerated()
            .map { "\($0.offset + 1): \($0.element)" }
            .joined(separator: "\n")

        return """
        Currency: \(currencyCode)

        Receipt lines:
        \(body)
        """
    }

    /// Reads the JSON object a text-completion engine returns.
    ///
    /// Tolerant on purpose: a model that has not been constrained to a schema tends to wrap
    /// its answer in prose or a fenced code block, and rejecting that would throw away a
    /// correct answer over its packaging. Apple Intelligence does not come through here —
    /// guided generation gives it the typed value directly.
    static func extraction(fromJSON text: String, dateParser: (String) -> Date?) -> ReceiptMLExtraction? {
        guard let object = firstJSONObject(in: text) else { return nil }

        let extraction = ReceiptMLExtraction(
            merchant: (object["merchant"] as? String).flatMap(cleanedMerchant),
            amount: number(object["total"]),
            subtotal: number(object["subtotal"]),
            tax: number(object["tax"]),
            tip: number(object["tip"]),
            date: (object["date"] as? String).flatMap(dateParser)
        )

        return extraction.hasUsefulValues ? extraction : nil
    }

    /// The first `{...}` that parses. Scanning for a balanced object rather than trusting the
    /// whole string is what survives "Here is the result:" and ```json fences.
    private static func firstJSONObject(in text: String) -> [String: Any]? {
        let characters = Array(text)
        guard let start = characters.firstIndex(of: "{") else { return nil }

        var depth = 0
        var insideString = false
        var escaped = false

        for index in start..<characters.count {
            let character = characters[index]

            if escaped {
                escaped = false
                continue
            }
            if character == "\\", insideString {
                escaped = true
                continue
            }
            if character == "\"" {
                insideString.toggle()
                continue
            }
            guard insideString == false else { continue }

            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                guard depth == 0 else { continue }
                let candidate = String(characters[start...index])
                guard let data = candidate.data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
        }

        return nil
    }

    /// Numbers arrive as a JSON number on a good day and as "$41.29" or "41,29" on a bad one.
    private static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        guard let string = value as? String else { return nil }

        let digits = string
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." || $0 == "-" }
        guard digits.isEmpty == false, let parsed = Double(digits) else { return nil }
        return parsed
    }

    private static func cleanedMerchant(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // A model asked for a field it cannot fill sometimes answers in words instead of
        // omitting it. Those answers must not become the vendor's name.
        let refusals = ["unknown", "n/a", "na", "none", "not visible", "not legible", "null"]
        guard trimmed.isEmpty == false,
              refusals.contains(trimmed.lowercased()) == false else { return nil }
        return trimmed
    }
}

extension ReceiptMLExtraction {
    /// Applies this extraction over a parsed receipt, field by field.
    ///
    /// The model wins wherever it produced a value; where it produced none, the parser's
    /// answer stands. "The model wins" is only meaningful about figures it actually read —
    /// letting its silence erase a value the parser found would make a better engine
    /// return less data than a worse one.
    ///
    /// Note what this does not do: nothing here checks the model's arithmetic. A total it
    /// invents is taken at face value, so the totals status is downgraded to `.unverified`
    /// rather than left claiming a reconciliation that no longer describes these figures.
    func applied(to parsed: ParsedReceiptData) -> ParsedReceiptData {
        var result = parsed

        if let merchant { result.merchant = merchant }
        if let amount { result.amount = amount }
        if let subtotal { result.subtotal = subtotal }
        if let tax { result.tax = tax }
        if let tip { result.tip = tip }
        if let date { result.date = date }

        let changedATotal = amount != nil || subtotal != nil || tax != nil || tip != nil
        if changedATotal {
            result.derivedTotals = []
            result.totalsStatus = .unverified
        }

        return result
    }
}

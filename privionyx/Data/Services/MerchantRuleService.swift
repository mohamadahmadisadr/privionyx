import Foundation

/// `nonisolated` because the parsing pipeline consults it off the main actor. `UserDefaults`
/// is documented as thread-safe, which is the only shared state here.
nonisolated struct MerchantRuleService {
    /// `UserDefaults` is thread-safe by documentation but not `Sendable` by type, and this
    /// struct has to cross actors to be useful. The unsafety is the annotation's, not the
    /// class's.
    nonisolated(unsafe) private let defaults: UserDefaults
    private let storageKey = "privionyx.merchant-category-rules"
    private let nameCorrectionKey = "privionyx.merchant-name-corrections"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func category(for merchant: String) -> ReceiptCategory? {
        let normalizedMerchant = normalize(merchant)
        guard normalizedMerchant.isEmpty == false,
              let rawValue = allRules()[normalizedMerchant] else {
            return nil
        }

        return ReceiptCategory(rawValue: rawValue)
    }

    func saveRule(merchant: String, category: ReceiptCategory) {
        let normalizedMerchant = normalize(merchant)
        guard normalizedMerchant.isEmpty == false,
              normalizedMerchant != normalize("Unknown Merchant") else {
            return
        }

        var rules = allRules()
        rules[normalizedMerchant] = category.rawValue
        defaults.set(rules, forKey: storageKey)
    }

    /// OCR misreads a given merchant's letterhead the same way every time — the same glyphs
    /// under the same font produce the same mistake. A correction the user makes once is
    /// therefore worth keeping: "Angler Sr" was read from a receipt that says "Angler SF",
    /// and the next scan of that restaurant will read it identically.
    func correctedMerchantName(forRecognized recognized: String) -> String? {
        let key = normalize(recognized)
        guard key.isEmpty == false else { return nil }
        return allNameCorrections()[key]
    }

    func saveMerchantCorrection(recognized: String, corrected: String) {
        let key = normalize(recognized)
        let value = corrected.trimmingCharacters(in: .whitespacesAndNewlines)

        guard key.isEmpty == false, value.isEmpty == false,
              key != normalize("Unknown Merchant"),
              // Nothing to learn when the user only restyled what was already read.
              key != normalize(value) else {
            return
        }

        var corrections = allNameCorrections()
        corrections[key] = value
        defaults.set(corrections, forKey: nameCorrectionKey)
    }

    private func allNameCorrections() -> [String: String] {
        defaults.dictionary(forKey: nameCorrectionKey) as? [String: String] ?? [:]
    }

    private func allRules() -> [String: String] {
        defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }

    private func normalize(_ merchant: String) -> String {
        merchant
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension MerchantRuleService: MerchantRuleProviding {}

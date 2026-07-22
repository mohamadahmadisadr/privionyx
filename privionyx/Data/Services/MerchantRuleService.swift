import Foundation

struct MerchantRuleService {
    private let defaults: UserDefaults
    private let storageKey = "privionyx.merchant-category-rules"

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

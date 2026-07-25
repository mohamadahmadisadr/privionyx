import Foundation

nonisolated protocol MerchantRuleProviding: Sendable {
    func category(for merchant: String) -> ReceiptCategory?
    func saveRule(merchant: String, category: ReceiptCategory)

    /// The name the user settled on last time this merchant was recognized this way.
    func correctedMerchantName(forRecognized recognized: String) -> String?

    /// Remembers that what recognition read as `recognized` is really `corrected`.
    func saveMerchantCorrection(recognized: String, corrected: String)
}

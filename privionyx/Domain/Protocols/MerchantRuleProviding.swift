import Foundation

protocol MerchantRuleProviding: Sendable {
    func category(for merchant: String) -> ReceiptCategory?
    func saveRule(merchant: String, category: ReceiptCategory)
}

import Foundation

struct ResolveCategoryUseCase {
    private let merchantRules: any MerchantRuleProviding

    init(merchantRules: any MerchantRuleProviding) {
        self.merchantRules = merchantRules
    }

    func execute(merchant: String, fallback: ReceiptCategory) -> ReceiptCategory {
        merchantRules.category(for: merchant) ?? fallback
    }
}

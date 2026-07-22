import Foundation

/// Applies the name the user has previously settled on for a merchant recognized this way.
///
/// Recognition fails consistently rather than randomly: the same letterhead in the same font
/// yields the same misreading every time, so a correction made once keeps paying. This is the
/// cheapest form of the per-merchant memory that separates a parser which improves with use
/// from one that makes the same mistake indefinitely.
struct ResolveMerchantUseCase {
    private let merchantRules: any MerchantRuleProviding

    init(merchantRules: any MerchantRuleProviding) {
        self.merchantRules = merchantRules
    }

    func execute(recognized: String) -> String {
        merchantRules.correctedMerchantName(forRecognized: recognized) ?? recognized
    }
}

import Foundation

nonisolated struct ParsedReceiptData: Hashable, Sendable {
    var merchant: String
    var amount: Double
    var subtotal: Double?
    var tax: Double?
    var tip: Double?
    var date: Date
    var category: ReceiptCategory
    var rawText: String
    var lineItems: [ReceiptLineItem]
    var notes: String
    /// Totals figures that were computed rather than read. Carried through to the review
    /// screen so the user is pointed at the numbers the app inferred.
    var derivedTotals: Set<ReceiptTotalsReconciler.Field> = []
    /// What reconciliation could establish about the totals block as a whole.
    var totalsStatus: ReceiptTotalsReconciler.Status = .unverified
}

import Foundation

protocol ReceiptRepository {
    /// Every receipt, newest first.
    ///
    /// There is no filtered variant. Filtering happens in memory over
    /// `PrivionyxAppState.receipts`, which holds the whole store, and a store-side predicate
    /// would be a second answer to the same question — slower per keystroke, and free to
    /// disagree with the first.
    func fetchReceipts() async throws -> [ReceiptItem]
    func upsertReceipt(_ receipt: ReceiptDraft) async throws
    func deleteReceipt(id: UUID) async throws
    /// One-off cleanup of data left by earlier builds. Run once at launch, before receipts
    /// are read.
    func performMaintenance() async throws
}

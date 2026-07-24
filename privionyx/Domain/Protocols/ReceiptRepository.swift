import Foundation

protocol ReceiptRepository {
    func fetchReceipts(matching query: SpendingQuery?) async throws -> [ReceiptItem]
    func upsertReceipt(_ receipt: ReceiptDraft) async throws
    func deleteReceipt(id: UUID) async throws
    /// One-off cleanup of data left by earlier builds. Run once at launch, before receipts
    /// are read.
    func performMaintenance() async throws
}

import Foundation

protocol ReceiptRepository {
    func fetchReceipts(matching query: SpendingQuery?) async throws -> [ReceiptItem]
    func upsertReceipt(_ receipt: ReceiptDraft) async throws
    func deleteReceipt(id: UUID) async throws
    func purgeLegacySeedData() async throws
}

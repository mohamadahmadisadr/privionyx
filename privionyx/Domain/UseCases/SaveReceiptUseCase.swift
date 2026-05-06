import Foundation

struct SaveReceiptUseCase {
    private let repository: ReceiptRepository

    init(repository: ReceiptRepository) {
        self.repository = repository
    }

    func execute(_ draft: ReceiptDraft) async throws {
        try await repository.upsertReceipt(draft)
    }
}

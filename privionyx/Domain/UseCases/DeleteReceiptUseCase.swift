import Foundation

struct DeleteReceiptUseCase {
    private let repository: ReceiptRepository

    init(repository: ReceiptRepository) {
        self.repository = repository
    }

    func execute(id: UUID) async throws {
        try await repository.deleteReceipt(id: id)
    }
}

import Foundation

struct FetchReceiptsUseCase {
    private let repository: ReceiptRepository

    init(repository: ReceiptRepository) {
        self.repository = repository
    }

    func execute(query: SpendingQuery? = nil) async throws -> [ReceiptItem] {
        try await repository.fetchReceipts(matching: query)
    }
}

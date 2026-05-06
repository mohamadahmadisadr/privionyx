import Observation
import CoreData
import Foundation
import UIKit

@MainActor
@Observable
final class PrivionyxAppState {
    private let container: PrivionyxAppContainer
    private var hasCompletedInitialLoad = false

    private(set) var receipts: [ReceiptItem] = []
    private(set) var receiptsVersion = 0
    private(set) var isBootstrapping = false
    private(set) var isLaunching = false
    private(set) var launchProgress: Double = 0
    private(set) var launchStatusText = "Preparing app..."
    var lastErrorMessage: String?

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    init(container: PrivionyxAppContainer) {
        self.container = container
    }

    func bootstrapIfNeeded() async {
        guard isBootstrapping == false, receipts.isEmpty else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        do {
            try await container.repository.purgeLegacySeedData()
            try await loadReceipts()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func initializeIfNeeded() async {
        guard hasCompletedInitialLoad == false, isLaunching == false else { return }
        isLaunching = true
        launchProgress = 0.08
        launchStatusText = "Loading saved receipts..."

        await bootstrapIfNeeded()
        launchProgress = 0.48

        launchStatusText = "Preparing app..."
        launchProgress = 1

        hasCompletedInitialLoad = true
        isLaunching = false
    }

    func refreshReceipts() async {
        do {
            try await loadReceipts()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func parseReceipt(from rawText: String) async -> ReceiptDraft {
        let parsed = await container.parser.parse(rawText: rawText)
        return ReceiptDraft(
            merchant: parsed.merchant,
            amount: parsed.amount,
            subtotal: parsed.subtotal,
            tax: parsed.tax,
            tip: parsed.tip,
            date: parsed.date,
            category: resolvedCategory(for: parsed.merchant, fallback: parsed.category),
            imageData: nil,
            rawText: parsed.rawText,
            lineItems: parsed.lineItems,
            notes: parsed.notes,
            status: .scanned
        )
    }

    func recognizeAndParseReceipt(from image: UIImage) async throws -> ReceiptDraft {
        let ocrResult = try await container.ocrService.recognizeText(in: image)
        let parsed = await container.parser.parse(ocrResult: ocrResult)

        return ReceiptDraft(
            merchant: parsed.merchant,
            amount: parsed.amount,
            subtotal: parsed.subtotal,
            tax: parsed.tax,
            tip: parsed.tip,
            date: parsed.date,
            category: resolvedCategory(for: parsed.merchant, fallback: parsed.category),
            imageData: nil,
            rawText: parsed.rawText,
            lineItems: parsed.lineItems,
            notes: parsed.notes,
            status: .scanned
        )
    }

    func enhanceReceiptImage(_ image: UIImage) -> UIImage {
        container.ocrService.enhanceReceiptImage(image)
    }

    func detectReceiptQuadrilateral(in image: UIImage) async -> ReceiptQuadrilateral? {
        await container.ocrService.detectReceiptQuadrilateral(in: image)
    }

    func cropReceiptImage(_ image: UIImage, quadrilateral: ReceiptQuadrilateral) -> UIImage {
        container.ocrService.cropReceiptImage(image, quadrilateral: quadrilateral)
    }

    func normalizeReceiptImage(_ image: UIImage) -> UIImage {
        container.ocrService.normalizedImage(image)
    }

    func saveReceipt(_ draft: ReceiptDraft) async throws {
        try await container.saveReceiptUseCase.execute(draft)
        container.merchantRuleService.saveRule(merchant: draft.merchant, category: draft.category)
        try await loadReceipts()
    }

    func deleteReceipt(id: UUID) async throws {
        try await container.deleteReceiptUseCase.execute(id: id)
        try await loadReceipts()
    }

    func makeQuery(
        searchText: String,
        selectedCategory: ReceiptCategory?,
        dateInterval: DateInterval? = nil,
        minimumAmount: Double? = nil,
        maximumAmount: Double? = nil
    ) -> SpendingQuery {
        container.queryService.makeQuery(
            searchText: searchText,
            selectedCategory: selectedCategory,
            dateInterval: dateInterval,
            minimumAmount: minimumAmount,
            maximumAmount: maximumAmount
        )
    }

    func filteredReceipts(
        searchText: String,
        selectedCategory: ReceiptCategory?,
        dateInterval: DateInterval? = nil,
        minimumAmount: Double? = nil,
        maximumAmount: Double? = nil
    ) -> [ReceiptItem] {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return receipts.filter { receipt in
            let matchesCategory = selectedCategory.map { receipt.category == $0 } ?? true
            let matchesSearch = normalizedSearch.isEmpty
                || receipt.merchant.localizedCaseInsensitiveContains(normalizedSearch)
                || receipt.notes.localizedCaseInsensitiveContains(normalizedSearch)
                || receipt.displayCategoryName.localizedCaseInsensitiveContains(normalizedSearch)
                || receipt.tags.contains(where: { $0.localizedCaseInsensitiveContains(normalizedSearch) })
                || PrivionyxCurrencyFormatter.string(for: receipt.amount).localizedCaseInsensitiveContains(normalizedSearch)
                || (receipt.rawText?.localizedCaseInsensitiveContains(normalizedSearch) ?? false)
            let matchesDate = dateInterval.map { $0.contains(receipt.date) } ?? true
            let matchesMinimumAmount = minimumAmount.map { receipt.amount >= $0 } ?? true
            let matchesMaximumAmount = maximumAmount.map { receipt.amount <= $0 } ?? true

            return matchesCategory && matchesSearch && matchesDate && matchesMinimumAmount && matchesMaximumAmount
        }
    }

    private func loadReceipts() async throws {
        receipts = try await container.fetchReceiptsUseCase.execute()
        receiptsVersion += 1
    }

    private func resolvedCategory(for merchant: String, fallback: ReceiptCategory) -> ReceiptCategory {
        container.merchantRuleService.category(for: merchant) ?? fallback
    }
}

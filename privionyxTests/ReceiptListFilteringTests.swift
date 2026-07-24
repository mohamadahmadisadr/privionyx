import Foundation
import Testing
@testable import privionyx

/// The receipt list's search and filtering, which had no coverage before the search index
/// replaced its per-keystroke `localizedCaseInsensitiveContains` calls. Matching is now done
/// against a pre-folded haystack, so these pin the semantics that change was meant to keep:
/// case- and accent-insensitive, across every field the list claims to search.
@MainActor
@Suite("Receipt list filtering")
struct ReceiptListFilteringTests {
    @Test("Search matches a merchant regardless of case or accents")
    func merchantSearchIsFolded() async throws {
        let viewModel = try await makeViewModel(with: [
            draft(merchant: "Café Luna", amount: 8.25),
            draft(merchant: "Hardware Depot", amount: 40)
        ])

        for query in ["café luna", "CAFE LUNA", "cafe"] {
            viewModel.searchText = query
            await viewModel.refresh()
            #expect(viewModel.filteredReceipts.map(\.merchant) == ["Café Luna"], "query: \(query)")
        }
    }

    @Test("Search matches notes, tags and raw OCR text")
    func searchCoversSecondaryFields() async throws {
        let viewModel = try await makeViewModel(with: [
            draft(merchant: "Alpha", amount: 10, notes: "reimbursable"),
            draft(merchant: "Beta", amount: 20, tags: ["client-dinner"]),
            draft(merchant: "Gamma", amount: 30, rawText: "STORE 118 TERMINAL 4")
        ])

        for (query, expected) in [("reimbursable", "Alpha"), ("client-dinner", "Beta"), ("terminal 4", "Gamma")] {
            viewModel.searchText = query
            await viewModel.refresh()
            #expect(viewModel.filteredReceipts.map(\.merchant) == [expected], "query: \(query)")
        }
    }

    @Test("Search matches the formatted amount")
    func searchMatchesFormattedAmount() async throws {
        let viewModel = try await makeViewModel(with: [
            draft(merchant: "Alpha", amount: 12.50),
            draft(merchant: "Beta", amount: 99.00)
        ])

        // Taken from the formatter so the expectation holds in any locale.
        viewModel.searchText = PrivionyxCurrencyFormatter.string(for: 12.50)
        await viewModel.refresh()

        #expect(viewModel.filteredReceipts.map(\.merchant) == ["Alpha"])
    }

    @Test("A query matching nothing yields no results")
    func unmatchedQuery() async throws {
        let viewModel = try await makeViewModel(with: [draft(merchant: "Alpha", amount: 10)])

        viewModel.searchText = "nothing here"
        await viewModel.refresh()

        #expect(viewModel.filteredReceipts.isEmpty)
        #expect(viewModel.groupedReceipts.isEmpty)
    }

    @Test("The category filter narrows to one category")
    func categoryFilter() async throws {
        let viewModel = try await makeViewModel(with: [
            draft(merchant: "Grocer", amount: 40, category: .grocery),
            draft(merchant: "Diner", amount: 25, category: .dining)
        ])

        viewModel.selectedCategory = .dining
        await viewModel.refresh()

        #expect(viewModel.filteredReceipts.map(\.merchant) == ["Diner"])
    }

    @Test("The date filter excludes receipts outside the range")
    func dateFilter() async throws {
        let lastYear = try #require(Calendar.current.date(byAdding: .year, value: -1, to: .now))
        let viewModel = try await makeViewModel(with: [
            draft(merchant: "Recent", amount: 10, date: .now),
            draft(merchant: "Old", amount: 10, date: lastYear)
        ])

        viewModel.selectedDateFilter = .thisMonth
        await viewModel.refresh()

        #expect(viewModel.filteredReceipts.map(\.merchant) == ["Recent"])
    }

    @Test("Filters combine rather than replacing one another")
    func filtersCombine() async throws {
        let viewModel = try await makeViewModel(with: [
            draft(merchant: "Corner Diner", amount: 25, category: .dining),
            draft(merchant: "Corner Grocer", amount: 25, category: .grocery)
        ])

        viewModel.searchText = "corner"
        viewModel.selectedCategory = .grocery
        await viewModel.refresh()

        #expect(viewModel.filteredReceipts.map(\.merchant) == ["Corner Grocer"])
    }

    @Test("With no filters every receipt is listed")
    func noFilters() async throws {
        let viewModel = try await makeViewModel(with: [
            draft(merchant: "Alpha", amount: 10),
            draft(merchant: "Beta", amount: 20)
        ])

        await viewModel.refresh()

        #expect(viewModel.filteredReceipts.count == 2)
        #expect(viewModel.hasActiveFilters == false)
    }

    @Test("Results are grouped by month, newest first")
    func monthGrouping() async throws {
        let calendar = Calendar.current
        let twoMonthsAgo = try #require(calendar.date(byAdding: .month, value: -2, to: .now))
        let viewModel = try await makeViewModel(with: [
            draft(merchant: "Older", amount: 10, date: twoMonthsAgo),
            draft(merchant: "Newer", amount: 20, date: .now)
        ])

        await viewModel.refresh()

        #expect(viewModel.groupedReceipts.count == 2)
        #expect(viewModel.groupedReceipts.first?.receipts.map(\.merchant) == ["Newer"])
        #expect(viewModel.groupedReceipts.last?.receipts.map(\.merchant) == ["Older"])
    }

    @Test("Clearing filters restores the full list")
    func clearingFilters() async throws {
        let viewModel = try await makeViewModel(with: [
            draft(merchant: "Alpha", amount: 10),
            draft(merchant: "Beta", amount: 20)
        ])

        viewModel.searchText = "alpha"
        await viewModel.refresh()
        #expect(viewModel.filteredReceipts.count == 1)

        viewModel.clearFilters()
        await viewModel.refresh()
        #expect(viewModel.filteredReceipts.count == 2)
    }

    // MARK: - Helpers

    /// An in-memory container, so each test gets its own store.
    private func makeViewModel(with drafts: [ReceiptDraft]) async throws -> ReceiptListViewModel {
        let state = PrivionyxAppState(container: .preview)
        for draft in drafts {
            try await state.saveReceipt(draft)
        }
        return ReceiptListViewModel(appState: state)
    }

    private func draft(
        merchant: String,
        amount: Double,
        category: ReceiptCategory = .shopping,
        date: Date = .now,
        tags: [String] = [],
        rawText: String? = nil,
        notes: String = ""
    ) -> ReceiptDraft {
        ReceiptDraft(
            merchant: merchant,
            amount: amount,
            date: date,
            category: category,
            tags: tags,
            rawText: rawText,
            notes: notes,
            status: .reviewed
        )
    }
}

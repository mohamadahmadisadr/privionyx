import Foundation
import Testing
@testable import privionyx

@Suite("Receipt search")
struct ReceiptSearchTests {
    private let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!

    private func receipt(
        merchant: String,
        amount: Double,
        category: String = "Dining",
        month: Int = 6,
        day: Int = 10
    ) -> AssistantReceipt {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day))!
        return AssistantReceipt(id: UUID(), merchant: merchant, amount: amount, tax: nil, date: date, category: category)
    }

    private func search(_ receipts: [AssistantReceipt]) -> ReceiptSearch {
        ReceiptSearch(context: AssistantContext(receipts: receipts, currencyCode: "USD", referenceDate: reference))
    }

    // MARK: - Intent

    @Test("A question about a figure attaches no receipts")
    func totalQuestionIsNotALookup() {
        let subject = search([receipt(merchant: "Amazon", amount: 30)])
        #expect(subject.results(for: "how much did I spend on dining this month?") == nil)
    }

    @Test("Greetings attach no receipts")
    func greetingIsNotALookup() {
        let subject = search([receipt(merchant: "Amazon", amount: 30)])
        #expect(subject.results(for: "hi") == nil)
    }

    @Test("With no receipts saved there is nothing to find")
    func emptyLibrary() {
        #expect(search([]).results(for: "find my amazon receipts") == nil)
    }

    // MARK: - Merchant

    @Test("A merchant lookup returns that merchant's receipts only")
    func merchantLookup() throws {
        let subject = search([
            receipt(merchant: "Amazon", amount: 30),
            receipt(merchant: "Amazon", amount: 20, day: 12),
            receipt(merchant: "Target", amount: 100)
        ])

        let result = try #require(subject.results(for: "find my Amazon receipts"))
        #expect(result.receipts.count == 2)
        #expect(result.receipts.allSatisfy { $0.merchant == "Amazon" })
        #expect(result.label.contains("Amazon"))
    }

    @Test("Results are newest first")
    func newestFirst() throws {
        let subject = search([
            receipt(merchant: "Amazon", amount: 30, day: 1),
            receipt(merchant: "Amazon", amount: 20, day: 20)
        ])

        let result = try #require(subject.results(for: "show my Amazon receipts"))
        #expect(result.receipts.first?.amount == 20)
    }

    @Test("A partial merchant name still finds the receipt")
    func partialMerchantName() throws {
        let subject = search([
            receipt(merchant: "Starbucks", amount: 8),
            receipt(merchant: "Target", amount: 40)
        ])

        let result = try #require(subject.results(for: "find starbuck"))
        #expect(result.receipts.count == 1)
        #expect(result.receipts.first?.merchant == "Starbucks")
    }

    @Test("A merchant with no receipts matches nothing rather than everything")
    func unknownMerchant() {
        let subject = search([receipt(merchant: "Amazon", amount: 30)])
        #expect(subject.results(for: "find my Ikea receipts") == nil)
    }

    // MARK: - Category, period, amount

    @Test("A category lookup filters to that category")
    func categoryLookup() throws {
        let subject = search([
            receipt(merchant: "Chipotle", amount: 14, category: "Dining"),
            receipt(merchant: "Shell", amount: 60, category: "Gas")
        ])

        let result = try #require(subject.results(for: "show me my dining receipts"))
        #expect(result.receipts.count == 1)
        #expect(result.receipts.first?.merchant == "Chipotle")
    }

    @Test("An everyday word for a category doesn't also have to appear on the receipt")
    func categorySynonymLookup() throws {
        let subject = search([
            receipt(merchant: "Blue Bottle", amount: 6, category: "Dining"),
            receipt(merchant: "Shell", amount: 60, category: "Gas")
        ])

        let result = try #require(subject.results(for: "find my coffee receipts"))
        #expect(result.receipts.map(\.merchant) == ["Blue Bottle"])
    }

    @Test("A named period narrows the results to it")
    func periodLookup() throws {
        let subject = search([
            receipt(merchant: "Amazon", amount: 30, month: 6),
            receipt(merchant: "Amazon", amount: 20, month: 5)
        ])

        let result = try #require(subject.results(for: "list my receipts from last month"))
        #expect(result.receipts.count == 1)
        #expect(result.receipts.first?.amount == 20)
        #expect(result.label.contains("last month"))
    }

    @Test("An amount floor excludes the receipts below it")
    func amountFloor() throws {
        let subject = search([
            receipt(merchant: "Amazon", amount: 120),
            receipt(merchant: "Target", amount: 30)
        ])

        let result = try #require(subject.results(for: "find receipts over $50"))
        #expect(result.receipts.count == 1)
        #expect(result.receipts.first?.amount == 120)
    }

    @Test("An amount ceiling excludes the receipts above it")
    func amountCeiling() throws {
        let subject = search([
            receipt(merchant: "Amazon", amount: 120),
            receipt(merchant: "Target", amount: 30)
        ])

        let result = try #require(subject.results(for: "show me receipts under 50"))
        #expect(result.receipts.map(\.amount) == [30])
    }

    @Test("Merchant and period combine")
    func combinedFilters() throws {
        let subject = search([
            receipt(merchant: "Amazon", amount: 30, month: 6),
            receipt(merchant: "Amazon", amount: 20, month: 5),
            receipt(merchant: "Target", amount: 99, month: 6)
        ])

        let result = try #require(subject.results(for: "find my Amazon receipts this month"))
        #expect(result.receipts.map(\.amount) == [30])
        #expect(result.label.contains("Amazon"))
        #expect(result.label.contains("this month"))
    }

    // MARK: - Volume

    @Test("Long result sets are capped and report what was left out")
    func truncation() throws {
        let receipts = (1...9).map { receipt(merchant: "Amazon", amount: Double($0), day: $0) }
        let result = try #require(search(receipts).results(for: "show my Amazon receipts"))

        #expect(result.receipts.count == ReceiptSearch.displayLimit)
        #expect(result.totalCount == 9)
        #expect(result.isTruncated)
    }

    // MARK: - Single receipt

    @Test("The biggest purchase comes back as one openable receipt")
    func largestPurchase() throws {
        let subject = search([
            receipt(merchant: "Amazon", amount: 30),
            receipt(merchant: "Dyson", amount: 312)
        ])

        let result = try #require(subject.results(for: "what was my biggest purchase?"))
        #expect(result.receipts.map(\.merchant) == ["Dyson"])
        #expect(result.label.contains("Largest"))
    }

    @Test("The most recent receipt comes back as one openable receipt")
    func mostRecent() throws {
        let subject = search([
            receipt(merchant: "Amazon", amount: 30, day: 2),
            receipt(merchant: "Target", amount: 12, day: 14)
        ])

        let result = try #require(subject.results(for: "what was my most recent receipt?"))
        #expect(result.receipts.map(\.merchant) == ["Target"])
    }

    @Test("Ranking categories names no single receipt to open")
    func biggestCategoryIsNotAReceipt() {
        let subject = search([
            receipt(merchant: "Amazon", amount: 30),
            receipt(merchant: "Dyson", amount: 312)
        ])

        #expect(subject.results(for: "what's my biggest category?") == nil)
    }
}

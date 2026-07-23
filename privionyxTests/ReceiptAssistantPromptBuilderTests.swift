import Foundation
import Testing
@testable import privionyx

@Suite("Assistant prompt builder")
struct ReceiptAssistantPromptBuilderTests {
    private func receipt(
        merchant: String,
        amount: Double,
        tax: Double?,
        daysAgo: Int,
        category: String = "Dining"
    ) -> AssistantReceipt {
        AssistantReceipt(
            id: UUID(),
            merchant: merchant,
            amount: amount,
            tax: tax,
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
            category: category
        )
    }

    @Test("Empty context yields a no-receipts digest")
    func emptyDigest() {
        let context = AssistantContext(receipts: [AssistantReceipt](), currencyCode: "USD")
        #expect(ReceiptAssistantPromptBuilder.digest(for: context) == "(no receipts saved yet)")
    }

    @Test("Digest lists newest receipts first")
    func digestIsNewestFirst() {
        let context = AssistantContext(
            receipts: [
                receipt(merchant: "Old", amount: 10, tax: nil, daysAgo: 30),
                receipt(merchant: "New", amount: 20, tax: nil, daysAgo: 1)
            ],
            currencyCode: "USD"
        )
        let digest = ReceiptAssistantPromptBuilder.digest(for: context)
        let newIndex = digest.range(of: "New")!.lowerBound
        let oldIndex = digest.range(of: "Old")!.lowerBound
        #expect(newIndex < oldIndex)
    }

    @Test("A missing tax renders as a dash, a present one with two decimals")
    func taxFormatting() {
        let withTax = AssistantContext(receipts: [receipt(merchant: "A", amount: 5, tax: 0.5, daysAgo: 1)], currencyCode: "USD")
        #expect(ReceiptAssistantPromptBuilder.digest(for: withTax).contains("| 0.50 |"))

        let noTax = AssistantContext(receipts: [receipt(merchant: "B", amount: 5, tax: nil, daysAgo: 1)], currencyCode: "USD")
        #expect(ReceiptAssistantPromptBuilder.digest(for: noTax).contains("| - |"))
    }

    @Test("Digest is capped at the prompt limit")
    func digestIsCapped() {
        let many = (0..<80).map { receipt(merchant: "M\($0)", amount: 1, tax: nil, daysAgo: $0) }
        let context = AssistantContext(receipts: many, currencyCode: "USD")
        let lines = ReceiptAssistantPromptBuilder.digest(for: context).split(separator: "\n")
        #expect(lines.count == ReceiptAssistantPromptBuilder.maximumReceiptsInPrompt)
    }

    @Test("Instructions carry the currency and grounding rule")
    func instructionsIncludeCurrency() {
        let context = AssistantContext(receipts: [AssistantReceipt](), currencyCode: "EUR")
        let instructions = ReceiptAssistantPromptBuilder.instructions(for: context)
        #expect(instructions.contains("EUR"))
        #expect(instructions.contains("never invent"))
    }
}

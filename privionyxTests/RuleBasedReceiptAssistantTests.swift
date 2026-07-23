import Foundation
import Testing
@testable import privionyx

@Suite("Rule-based assistant")
@MainActor
struct RuleBasedReceiptAssistantTests {
    private let reference = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15))!

    private func receipt(
        merchant: String,
        amount: Double,
        tax: Double? = nil,
        category: String = "Dining",
        month: Int = 6,
        day: Int = 10
    ) -> AssistantReceipt {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day))!
        return AssistantReceipt(id: UUID(), merchant: merchant, amount: amount, tax: tax, date: date, category: category)
    }

    private func context(_ receipts: [AssistantReceipt]) -> AssistantContext {
        AssistantContext(receipts: receipts, currencyCode: "USD", referenceDate: reference)
    }

    private let assistant = RuleBasedReceiptAssistant()

    @Test("With no receipts it points the user at the camera")
    func empty() async throws {
        let reply = try await assistant.reply(to: "what did I spend?", context: context([]))
        #expect(reply.contains("Camera"))
    }

    @Test("A merchant question totals that merchant only")
    func merchantQuery() async throws {
        let ctx = context([
            receipt(merchant: "Amazon", amount: 30),
            receipt(merchant: "Amazon", amount: 20),
            receipt(merchant: "Target", amount: 100)
        ])
        let reply = try await assistant.reply(to: "how much have I spent at Amazon?", context: ctx)
        #expect(reply.contains("Amazon"))
        #expect(reply.contains("50"))
        #expect(reply.contains("100") == false)
    }

    @Test("A category question narrows to that category")
    func categoryQuery() async throws {
        let ctx = context([
            receipt(merchant: "Cafe", amount: 12, category: "Dining"),
            receipt(merchant: "Airline", amount: 400, category: "Travel")
        ])
        let reply = try await assistant.reply(to: "how much on dining?", context: ctx)
        #expect(reply.contains("Dining"))
        #expect(reply.contains("12"))
    }

    @Test("Biggest purchase names the largest single receipt")
    func biggestPurchase() async throws {
        let ctx = context([
            receipt(merchant: "Cheap", amount: 5),
            receipt(merchant: "Splurge", amount: 250),
            receipt(merchant: "Mid", amount: 40)
        ])
        let reply = try await assistant.reply(to: "what was my biggest purchase?", context: ctx)
        #expect(reply.contains("Splurge"))
        #expect(reply.contains("250"))
    }

    @Test("A time range narrows the total")
    func timeRangeQuery() async throws {
        let ctx = context([
            receipt(merchant: "June", amount: 10, month: 6),
            receipt(merchant: "May", amount: 90, month: 5)
        ])
        let reply = try await assistant.reply(to: "how much did I spend last month?", context: ctx)
        #expect(reply.contains("90"))
        #expect(reply.contains("last month"))
    }

    @Test("Averages are reported per receipt")
    func averageQuery() async throws {
        let ctx = context([
            receipt(merchant: "A", amount: 10),
            receipt(merchant: "B", amount: 30)
        ])
        let reply = try await assistant.reply(to: "what's my average receipt?", context: ctx)
        #expect(reply.contains("20"))
    }

    @Test("Comparison answers with both months")
    func comparison() async throws {
        let ctx = context([
            receipt(merchant: "A", amount: 120, month: 6),
            receipt(merchant: "B", amount: 100, month: 5)
        ])
        let reply = try await assistant.reply(to: "compare this month to last month", context: ctx)
        #expect(reply.contains("120"))
        #expect(reply.contains("100"))
    }

    @Test("Unusual spending surfaces the outlier")
    func anomalies() async throws {
        let ctx = context([
            receipt(merchant: "A", amount: 10, category: "Dining"),
            receipt(merchant: "B", amount: 11, category: "Dining"),
            receipt(merchant: "C", amount: 12, category: "Dining"),
            receipt(merchant: "Splurge", amount: 95, category: "Dining")
        ])
        let reply = try await assistant.reply(to: "any unusual spending?", context: ctx)
        #expect(reply.contains("Splurge"))
    }

    @Test("\"Last time\" is understood as the most recent receipt, not a month total", arguments: [
        "what did I spend last time how much and what?",
        "my last receipt",
        "what did I just spend?"
    ])
    func lastReceiptPhrasing(query: String) async throws {
        let ctx = context([
            receipt(merchant: "Older", amount: 200, day: 1),
            receipt(merchant: "Uber", amount: 24.50, category: "Travel", day: 12)
        ])
        let reply = try await assistant.reply(to: query, context: ctx)
        #expect(reply.contains("Uber"))
        #expect(reply.contains("24.50"))
    }

    @Test("An unrecognized question still gives a useful overview")
    func fallback() async throws {
        let ctx = context([receipt(merchant: "A", amount: 10)])
        let reply = try await assistant.reply(to: "tell me something interesting", context: ctx)
        #expect(reply.isEmpty == false)
    }

    @Test("A greeting gets a friendly reply, not a spending dump")
    func greeting() async throws {
        let ctx = context([receipt(merchant: "A", amount: 10)])
        let reply = try await assistant.reply(to: "hey", context: ctx)
        #expect(reply.lowercased().contains("hey") || reply.lowercased().contains("hi"))
    }

    @Test("\"How am I doing\" returns a multi-fact snapshot")
    func snapshot() async throws {
        let ctx = context([
            receipt(merchant: "Cafe", amount: 30, category: "Dining", month: 6),
            receipt(merchant: "Air", amount: 200, category: "Travel", month: 6),
            receipt(merchant: "Old", amount: 100, month: 5)
        ])
        let reply = try await assistant.reply(to: "how am I doing this month?", context: ctx)
        #expect(reply.contains("230")) // 30 + 200 this month
        #expect(reply.lowercased().contains("this month"))
    }

    @Test("A saving question points at the biggest category")
    func saving() async throws {
        let ctx = context([
            receipt(merchant: "Cafe", amount: 20, category: "Dining"),
            receipt(merchant: "Air", amount: 500, category: "Travel")
        ])
        let reply = try await assistant.reply(to: "where can I save money?", context: ctx)
        #expect(reply.contains("Travel"))
    }

    @Test("A \"when\" question names the most recent visit to a merchant")
    func when() async throws {
        let ctx = context([
            receipt(merchant: "Costco", amount: 40, day: 2),
            receipt(merchant: "Costco", amount: 60, day: 14)
        ])
        let reply = try await assistant.reply(to: "when did I last go to Costco?", context: ctx)
        #expect(reply.contains("Costco"))
        #expect(reply.contains("60")) // the later visit
    }

    @Test("A bare merchant question is answered even without spend keywords")
    func entityAwareFallback() async throws {
        let ctx = context([
            receipt(merchant: "Netflix", amount: 15),
            receipt(merchant: "Netflix", amount: 15, day: 20)
        ])
        let reply = try await assistant.reply(to: "how much at Netflix", context: ctx)
        #expect(reply.contains("Netflix"))
        #expect(reply.contains("30"))
    }

    @Test("Same question always answers the same way (deterministic variation)")
    func deterministic() async throws {
        let ctx = context([receipt(merchant: "A", amount: 10), receipt(merchant: "B", amount: 20)])
        let first = try await assistant.reply(to: "what did I spend this month?", context: ctx)
        let second = try await assistant.reply(to: "what did I spend this month?", context: ctx)
        #expect(first == second)
    }
}

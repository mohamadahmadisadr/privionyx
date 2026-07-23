import Foundation

/// Builds the grounding prompt shared by every language-model assistant engine, so an
/// on-device Gemma answer and an Apple Intelligence answer reason over the receipt data in
/// exactly the same shape. Rule-based engines don't use this — they compute answers directly.
enum ReceiptAssistantPromptBuilder {
    /// Receipts included in the prompt digest, newest first. Bounds the context window.
    static let maximumReceiptsInPrompt = 60

    /// System instructions establishing the assistant's role and handing it the receipt data
    /// as the only source of truth it may reason from.
    ///
    /// The prompt leads with a pre-computed SUMMARY of the figures a model would otherwise
    /// have to add up itself — small on-device models are unreliable at arithmetic over many
    /// rows, so every total, average, and ranking is handed to it as fact. The raw RECEIPTS
    /// then let it answer anything the summary doesn't already cover.
    static func instructions(for context: AssistantContext) -> String {
        """
        You are the expense assistant inside Privionyx, a private on-device receipt tracker.
        Answer only from the data below — never invent merchants, amounts, or dates.
        Trust the SUMMARY figures as exact; they are computed for you, so don't re-add numbers \
        yourself. Use the RECEIPTS for anything the summary doesn't cover.
        If the data cannot answer the question, say so plainly and suggest what you can answer.
        Be conversational and specific. Keep everyday answers to a few sentences, but go longer \
        with a short bulleted list when the question genuinely calls for a breakdown.
        Format money as \(context.currencyCode). Today is \(context.referenceDate.formatted(date: .abbreviated, time: .omitted)).

        SUMMARY:
        \(summary(for: context))

        RECEIPTS (merchant | amount | tax | date | category), newest first:
        \(digest(for: context))
        """
    }

    /// Pre-computed aggregates the model can quote verbatim instead of deriving. Everything
    /// here comes from `ExpenseAnalytics`, the same figures the built-in engine answers with.
    static func summary(for context: AssistantContext) -> String {
        let analytics = ExpenseAnalytics(context: context)
        guard analytics.isEmpty == false else { return "(no receipts saved yet)" }

        func money(_ value: Double) -> String { String(format: "%.2f", value) }

        let all = analytics.aggregate(analytics.receipts)
        let thisMonth = analytics.aggregate(in: analytics.currentMonth)
        let lastMonth = analytics.aggregate(in: analytics.previousMonth)

        var lines: [String] = [
            "All time: \(money(all.total)) across \(all.count) receipts (avg \(money(all.average)))",
            "This month: \(money(thisMonth.total)) across \(thisMonth.count)",
            "Last month: \(money(lastMonth.total)) across \(lastMonth.count)"
        ]

        let categories = analytics.byCategory(analytics.receipts).prefix(5)
        if categories.isEmpty == false {
            lines.append("Top categories (all time): " + categories.map { "\($0.name) \(money($0.total))" }.joined(separator: ", "))
        }

        let merchants = analytics.byMerchant(analytics.receipts).prefix(5)
        if merchants.isEmpty == false {
            lines.append("Top merchants (all time): " + merchants.map { "\($0.name) \(money($0.total))" }.joined(separator: ", "))
        }

        if let biggest = analytics.largestPurchase(in: analytics.receipts) {
            lines.append("Biggest single purchase: \(money(biggest.amount)) at \(biggest.merchant) on \(biggest.date.formatted(date: .numeric, time: .omitted))")
        }

        if let recent = analytics.mostRecent {
            let tax = recent.tax.map { ", tax \(money($0))" } ?? ""
            lines.append("Most recent receipt (\"last\"/\"latest\" purchase): \(money(recent.amount)) at \(recent.merchant) on \(recent.date.formatted(date: .numeric, time: .omitted)) (\(recent.category))\(tax)")
        }

        return lines.joined(separator: "\n")
    }

    /// The newest receipts flattened to one line each, capped at `maximumReceiptsInPrompt`.
    static func digest(for context: AssistantContext) -> String {
        let recent = context.receipts
            .sorted { $0.date > $1.date }
            .prefix(maximumReceiptsInPrompt)

        guard recent.isEmpty == false else { return "(no receipts saved yet)" }

        return recent.map { receipt in
            let tax = receipt.tax.map { String(format: "%.2f", $0) } ?? "-"
            return "\(receipt.merchant) | \(String(format: "%.2f", receipt.amount)) | \(tax) | \(receipt.date.formatted(date: .numeric, time: .omitted)) | \(receipt.category)"
        }
        .joined(separator: "\n")
    }

    /// Prompt chips a conversational LLM engine offers above the composer.
    static func suggestedPrompts(for context: AssistantContext) -> [String] {
        guard context.receipts.isEmpty == false else {
            return ["What can you help me with?"]
        }
        return [
            "Where is my money going this month?",
            "Anything I should cut back on?",
            "Summarize my last receipt",
            "Compare this month to last month"
        ]
    }
}

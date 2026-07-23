import Foundation

/// A conversational engine that answers questions about the user's receipts.
///
/// Implementations are interchangeable — see `AssistantBackend` for the registry the
/// user picks from in Settings. Adding a new engine means conforming here and adding
/// a case to `AssistantBackend`; nothing in the presentation layer changes.
@MainActor
protocol ReceiptAssistant {
    /// Whether this engine can currently serve requests on this device.
    func availability() async -> AssistantAvailability

    /// Chips offered above the composer. Engines may tailor these to the data at hand.
    func suggestedPrompts(for context: AssistantContext) -> [String]

    /// Answer `prompt` using `context` as the only source of truth about spending.
    func reply(to prompt: String, context: AssistantContext) async throws -> String

    /// Progressive form of `reply`, yielding the answer so far. Engines that cannot
    /// stream inherit the default, which emits the complete answer as one element.
    func streamReply(to prompt: String, context: AssistantContext) -> AsyncThrowingStream<String, Error>

    /// Give the engine a chance to warm up before the user types. Optional.
    func prepareForUse(context: AssistantContext)
}

extension ReceiptAssistant {
    func streamReply(to prompt: String, context: AssistantContext) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    continuation.yield(try await reply(to: prompt, context: context))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func prepareForUse(context: AssistantContext) {}
}

enum AssistantAvailability: Equatable, Sendable {
    case available
    /// The engine exists but cannot run right now — the reason is shown to the user.
    case unavailable(reason: String)

    var isAvailable: Bool { self == .available }

    var reason: String? {
        switch self {
        case .available: nil
        case let .unavailable(reason): reason
        }
    }
}

/// Immutable snapshot of the spending data an assistant is allowed to reason over.
struct AssistantContext: Sendable {
    let receipts: [AssistantReceipt]
    let currencyCode: String
    let referenceDate: Date

    init(receipts: [AssistantReceipt], currencyCode: String, referenceDate: Date = .now) {
        self.receipts = receipts
        self.currencyCode = currencyCode
        self.referenceDate = referenceDate
    }
}

/// Flattened receipt carrying only what an assistant needs, keeping engines free of
/// persistence and image types.
struct AssistantReceipt: Sendable, Identifiable, Equatable {
    let id: UUID
    let merchant: String
    let amount: Double
    let tax: Double?
    let date: Date
    let category: String
}

extension AssistantContext {
    init(receipts: [ReceiptItem], currencyCode: String = PrivionyxCurrencyFormatter.currentCurrencyCode, referenceDate: Date = .now) {
        self.init(
            receipts: receipts.map {
                AssistantReceipt(
                    id: $0.id,
                    merchant: $0.merchant,
                    amount: $0.amount,
                    tax: $0.tax,
                    date: $0.date,
                    // The canonical category, not a custom display label — analytics,
                    // budgets, and the dashboard all key spending by the base category, so a
                    // receipt with a custom name still counts toward its category's budget.
                    category: $0.category.rawValue
                )
            },
            currencyCode: currencyCode,
            referenceDate: referenceDate
        )
    }

    /// Receipts dated within the calendar month of `referenceDate`.
    var currentMonthReceipts: [AssistantReceipt] {
        receipts.filter { Calendar.current.isDate($0.date, equalTo: referenceDate, toGranularity: .month) }
    }

    var mostRecentReceipt: AssistantReceipt? {
        receipts.max { $0.date < $1.date }
    }
}

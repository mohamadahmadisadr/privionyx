import Foundation
import Observation

@MainActor
@Observable
final class AssistantViewModel {
    private let appState: PrivionyxAppState

    private(set) var backend: AssistantBackend
    private var assistant: any ReceiptAssistant

    /// Engines, built once and reused.
    ///
    /// `makeAssistant()` returns a fresh instance, and the language-model engines hold their
    /// expensive state in instance properties — a loaded LiteRT `Engine`, a warmed
    /// `LanguageModelSession`. Since `prepare(backend:)` runs on every appearance of the
    /// Assistant tab, building a new engine each time discarded a multi-gigabyte model load
    /// and paid for it again on the next question.
    ///
    /// Only the selected engine and the built-in one are kept: switching backends releases
    /// the engine being switched away from, so two models' weights are never resident at
    /// once. The built-in engine is stateless, so keeping it costs nothing.
    @ObservationIgnored private var engines: [AssistantBackend: any ReceiptAssistant] = [:]

    var input = ""
    private(set) var messages: [AssistantMessage] = []
    private(set) var suggestions: [String] = []
    private(set) var isResponding = false
    /// Set when the selected engine can't run and the built-in one is standing in.
    private(set) var fallbackNotice: String?

    // `.rules` rather than `.fallback`: a default argument is evaluated in the caller's
    // isolation, and the static is main-actor bound.
    init(appState: PrivionyxAppState, backend: AssistantBackend = .rules) {
        self.appState = appState
        self.backend = backend

        let initial = backend.makeAssistant()
        self.assistant = initial
        self.engines = [backend: initial]
    }

    /// The cached engine for `backend`, built on first use.
    private func engine(for backend: AssistantBackend) -> any ReceiptAssistant {
        if let existing = engines[backend] { return existing }

        let created = backend.makeAssistant()
        engines[backend] = created
        return created
    }

    var canSend: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && isResponding == false
    }

    /// Resolves the engine and seeds the greeting. Safe to call on every appearance.
    func prepare(backend: AssistantBackend) async {
        let backendChanged = backend != self.backend
        self.backend = backend

        // Release the engine being switched away from before building the new one, so a
        // model the user is no longer using doesn't stay resident.
        if backendChanged {
            engines = engines.filter { $0.key == backend || $0.key == .fallback }
        }

        let candidate = engine(for: backend)
        let availability = await candidate.availability()

        switch availability {
        case .available:
            assistant = candidate
            fallbackNotice = nil
        case let .unavailable(reason):
            assistant = engine(for: .fallback)
            fallbackNotice = "\(reason) Using the built-in engine instead."
        }

        let context = makeContext()
        suggestions = assistant.suggestedPrompts(for: context)
        assistant.prepareForUse(context: context)

        if messages.isEmpty {
            messages = [AssistantMessage(role: .assistant, text: greeting)]
        } else if backendChanged {
            messages.append(AssistantMessage(role: .assistant, text: "Switched to the \(backend.title) engine. Ask away."))
        }
    }

    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }
        input = ""
        Task { await exchange(text) }
    }

    func send(suggestion: String) {
        guard isResponding == false else { return }
        Task { await exchange(suggestion) }
    }

    private func exchange(_ text: String) async {
        messages.append(AssistantMessage(role: .user, text: text))
        isResponding = true
        defer {
            isResponding = false
            // Offer follow-ups tailored to what was just asked so the conversation flows.
            suggestions = AssistantSuggestions.followUps(to: text, context: makeContext())
        }

        // Resolved up front from the question, not from the answer: whichever engine is
        // selected, the cards under the reply are the user's actual receipts.
        let matches = receiptMatches(for: text)

        // Streaming engines emit the answer so far; the reply bubble is inserted on the
        // first chunk and rewritten in place after that.
        let replyID = UUID()

        do {
            for try await partial in assistant.streamReply(to: text, context: makeContext()) {
                guard partial.isEmpty == false else { continue }
                upsertReply(id: replyID, text: partial, matchedReceipts: matches)
            }
        } catch is CancellationError {
            return
        } catch {
            await recoverWithBuiltIn(after: error, prompt: text, replyID: replyID, matches: matches)
        }

        if messages.contains(where: { $0.id == replyID }) == false {
            upsertReply(id: replyID, text: "I couldn't come up with an answer for that one.", matchedReceipts: matches)
        }
    }

    /// The receipts a question is asking to see, if it is asking to see any.
    private func receiptMatches(for prompt: String) -> AssistantMessage.ReceiptMatches? {
        guard let result = ReceiptSearch(context: makeContext()).results(for: prompt) else { return nil }

        return AssistantMessage.ReceiptMatches(
            ids: result.receipts.map(\.id),
            caption: result.label,
            hiddenCount: result.totalCount - result.receipts.count
        )
    }

    /// The saved receipts behind a reply's cards, re-read on every render so an edit or a
    /// deletion in the meantime is reflected rather than opening a receipt that is gone.
    func matchedReceipts(in message: AssistantMessage) -> [ReceiptItem] {
        guard let matched = message.matchedReceipts else { return [] }

        let byID = Dictionary(appState.receipts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return matched.ids.compactMap { byID[$0] }
    }

    /// A device can report an engine as available and still fail to generate. Rather
    /// than hand the user an error, answer with the built-in engine and switch to it so
    /// the next question works too.
    private func recoverWithBuiltIn(
        after error: Error,
        prompt: String,
        replyID: UUID,
        matches: AssistantMessage.ReceiptMatches?
    ) async {
        guard backend != .fallback else {
            upsertReply(id: replyID, text: error.localizedDescription)
            return
        }

        let builtIn = engine(for: .fallback)

        guard let recovered = try? await builtIn.reply(to: prompt, context: makeContext()) else {
            upsertReply(id: replyID, text: error.localizedDescription)
            return
        }

        assistant = builtIn
        suggestions = builtIn.suggestedPrompts(for: makeContext())
        fallbackNotice = "\(error.localizedDescription) Switched to the built-in engine."
        upsertReply(id: replyID, text: recovered, matchedReceipts: matches)
    }

    private func upsertReply(id: UUID, text: String, matchedReceipts: AssistantMessage.ReceiptMatches? = nil) {
        let message = AssistantMessage(id: id, role: .assistant, text: text, matchedReceipts: matchedReceipts)

        if let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
    }

    private func makeContext() -> AssistantContext {
        AssistantContext(receipts: appState.receipts)
    }

    private var greeting: String {
        appState.receipts.isEmpty
            ? "Hi! I'm your expense assistant. Scan a receipt from the Camera tab and I can break down totals, categories, and merchants for you."
            : "Hi! I'm your expense assistant. Ask me anything about your \(appState.receipts.count) saved receipts, or tap a suggestion below."
    }
}

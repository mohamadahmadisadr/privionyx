import Foundation
import Observation

@MainActor
@Observable
final class AssistantViewModel {
    private let appState: PrivionyxAppState

    private(set) var backend: AssistantBackend
    private var assistant: any ReceiptAssistant

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
        self.assistant = backend.makeAssistant()
    }

    var canSend: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false && isResponding == false
    }

    /// Resolves the engine and seeds the greeting. Safe to call on every appearance.
    func prepare(backend: AssistantBackend) async {
        let backendChanged = backend != self.backend
        self.backend = backend

        let candidate = backend.makeAssistant()
        let availability = await candidate.availability()

        switch availability {
        case .available:
            assistant = candidate
            fallbackNotice = nil
        case let .unavailable(reason):
            assistant = AssistantBackend.fallback.makeAssistant()
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

        // Streaming engines emit the answer so far; the reply bubble is inserted on the
        // first chunk and rewritten in place after that.
        let replyID = UUID()

        do {
            for try await partial in assistant.streamReply(to: text, context: makeContext()) {
                guard partial.isEmpty == false else { continue }
                upsertReply(id: replyID, text: partial)
            }
        } catch is CancellationError {
            return
        } catch {
            await recoverWithBuiltIn(after: error, prompt: text, replyID: replyID)
        }

        if messages.contains(where: { $0.id == replyID }) == false {
            upsertReply(id: replyID, text: "I couldn't come up with an answer for that one.")
        }
    }

    /// A device can report an engine as available and still fail to generate. Rather
    /// than hand the user an error, answer with the built-in engine and switch to it so
    /// the next question works too.
    private func recoverWithBuiltIn(after error: Error, prompt: String, replyID: UUID) async {
        guard backend != .fallback else {
            upsertReply(id: replyID, text: error.localizedDescription)
            return
        }

        let builtIn = AssistantBackend.fallback.makeAssistant()

        guard let recovered = try? await builtIn.reply(to: prompt, context: makeContext()) else {
            upsertReply(id: replyID, text: error.localizedDescription)
            return
        }

        assistant = builtIn
        suggestions = builtIn.suggestedPrompts(for: makeContext())
        fallbackNotice = "\(error.localizedDescription) Switched to the built-in engine."
        upsertReply(id: replyID, text: recovered)
    }

    private func upsertReply(id: UUID, text: String) {
        let message = AssistantMessage(id: id, role: .assistant, text: text)

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

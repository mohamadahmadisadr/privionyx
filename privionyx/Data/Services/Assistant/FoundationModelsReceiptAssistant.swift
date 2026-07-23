import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Assistant backed by Apple's on-device language model. Still fully private — the
/// model runs locally — but it needs an Apple Intelligence–capable device with the
/// feature switched on, so `availability()` may report it unusable.
///
/// The session is kept alive across turns so the model can follow up on what was just
/// asked. Receipt data lives in the session instructions, so the session is rebuilt
/// whenever that data changes; otherwise the model would answer from a stale snapshot.
@MainActor
final class FoundationModelsReceiptAssistant: ReceiptAssistant {
    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    /// Instructions the live session was built from; a mismatch means it must be rebuilt.
    private var sessionInstructions: String?
    #endif

    func availability() async -> AssistantAvailability {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default

        switch model.availability {
        case .available:
            guard model.supportsLocale() else {
                return .unavailable(reason: "Apple Intelligence doesn't support your current language yet.")
            }
            return .available
        case let .unavailable(reason):
            return .unavailable(reason: description(for: reason))
        @unknown default:
            return .unavailable(reason: "Apple Intelligence is unavailable on this device.")
        }
        #else
        return .unavailable(reason: "This build was compiled without Apple Intelligence support.")
        #endif
    }

    func suggestedPrompts(for context: AssistantContext) -> [String] {
        ReceiptAssistantPromptBuilder.suggestedPrompts(for: context)
    }

    /// Builds and warms the session so the first answer isn't paying model load cost.
    func prepareForUse(context: AssistantContext) {
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else { return }
        makeSession(for: context).prewarm()
        #endif
    }

    func reply(to prompt: String, context: AssistantContext) async throws -> String {
        #if canImport(FoundationModels)
        do {
            let session = try await readySession(for: context)
            return try await session.respond(to: prompt).content
        } catch {
            throw mapped(error)
        }
        #else
        throw AssistantError.unavailable("This build was compiled without Apple Intelligence support.")
        #endif
    }

    func streamReply(to prompt: String, context: AssistantContext) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                #if canImport(FoundationModels)
                do {
                    let session = try await readySession(for: context)

                    // Snapshots carry the answer so far, not deltas.
                    for try await snapshot in session.streamResponse(to: prompt) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: mapped(error))
                }
                #else
                continuation.finish(throwing: AssistantError.unavailable("This build was compiled without Apple Intelligence support."))
                #endif
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Session

    #if canImport(FoundationModels)
    private func readySession(for context: AssistantContext) async throws -> LanguageModelSession {
        let availability = await availability()
        guard availability.isAvailable else {
            throw AssistantError.unavailable(availability.reason ?? "Apple Intelligence is unavailable.")
        }

        let session = makeSession(for: context)
        guard session.isResponding == false else {
            throw AssistantError.generationFailed("Still working on the previous question — give it a moment.")
        }
        return session
    }

    /// Returns the live session, rebuilding it when the receipt data behind its
    /// instructions has changed.
    private func makeSession(for context: AssistantContext) -> LanguageModelSession {
        let instructions = instructions(for: context)

        if let session, sessionInstructions == instructions {
            return session
        }

        let session = LanguageModelSession(instructions: instructions)
        self.session = session
        sessionInstructions = instructions
        return session
    }

    private func description(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            "This device doesn't support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            "Turn on Apple Intelligence in Settings to use this engine."
        case .modelNotReady:
            "The on-device model is still downloading. Try again shortly."
        @unknown default:
            "Apple Intelligence is unavailable right now."
        }
    }

    /// Turns anything the framework throws into a message worth showing a user.
    /// `SystemLanguageModel` can report itself available on a device that still cannot
    /// generate (notably the Simulator), and those failures arrive as opaque errors —
    /// so unrecognised errors get a plain explanation rather than a raw NSError dump.
    private func mapped(_ error: Error) -> Error {
        if let error = error as? AssistantError {
            return error
        }
        if let error = error as? LanguageModelSession.GenerationError {
            return AssistantError.generationFailed(message(for: error))
        }
        if error is CancellationError {
            return error
        }
        return AssistantError.generationFailed("The on-device model isn't able to answer right now.")
    }

    private func message(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize:
            "That's more receipt history than I can weigh at once. Try narrowing the question to a month or a category."
        case .guardrailViolation:
            "I wasn't able to answer that one. Try rephrasing it around your spending."
        case .assetsUnavailable:
            "The on-device model isn't ready yet. Try again shortly."
        case .rateLimited:
            "Too many requests in a row. Give it a moment and try again."
        case .unsupportedLanguageOrLocale:
            "Apple Intelligence doesn't support your current language yet."
        default:
            "The on-device model couldn't complete that request."
        }
    }
    #endif

    // MARK: - Prompt

    private func instructions(for context: AssistantContext) -> String {
        ReceiptAssistantPromptBuilder.instructions(for: context)
    }
}

enum AssistantError: LocalizedError {
    case unavailable(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unavailable(message): message
        case let .generationFailed(message): message
        }
    }
}

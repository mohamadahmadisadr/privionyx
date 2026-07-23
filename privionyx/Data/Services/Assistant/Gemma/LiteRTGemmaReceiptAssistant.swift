import Foundation

#if canImport(LiteRTLM)
import LiteRTLM
#endif

/// Assistant backed by Google's Gemma 4, running fully on-device through the LiteRT-LM
/// runtime with Metal (GPU) acceleration. Fully private — the model and every token stay
/// on the device — but it requires the ~2.6 GB weights to be downloaded first (see
/// `GemmaModelManager`) and a device with enough memory to load them.
///
/// The whole runtime path is guarded by `#if canImport(LiteRTLM)` so the app builds and
/// ships before the Swift package is added, mirroring `FoundationModelsReceiptAssistant`.
/// Until the package is linked, the engine simply reports itself unavailable and the
/// assistant falls back to the built-in engine.
@MainActor
final class LiteRTGemmaReceiptAssistant: ReceiptAssistant {
    private let modelManager: GemmaModelManager

    #if canImport(LiteRTLM)
    private var engine: Engine?
    /// URL the live engine was built from; a change means it must be rebuilt.
    private var engineModelURL: URL?
    /// Instructions the live conversation was grounded with; a mismatch means the receipt
    /// data changed and the conversation must be rebuilt so answers aren't stale.
    private var conversation: Conversation?
    private var conversationInstructions: String?
    #endif

    init(modelManager: GemmaModelManager = .shared) {
        self.modelManager = modelManager
    }

    func availability() async -> AssistantAvailability {
        #if canImport(LiteRTLM)
        switch modelManager.state {
        case .unsupported:
            return .unavailable(reason: "This device doesn't have enough memory to run Gemma on-device.")
        case .notDownloaded, .failed:
            return .unavailable(reason: "Download the Gemma model in Settings to use this engine.")
        case .downloading:
            return .unavailable(reason: "The Gemma model is still downloading. It'll be ready shortly.")
        case .ready:
            return .available
        }
        #else
        return .unavailable(reason: "This build was compiled without the Gemma runtime.")
        #endif
    }

    func suggestedPrompts(for context: AssistantContext) -> [String] {
        ReceiptAssistantPromptBuilder.suggestedPrompts(for: context)
    }

    func reply(to prompt: String, context: AssistantContext) async throws -> String {
        #if canImport(LiteRTLM)
        do {
            let conversation = try await readyConversation(for: context)
            let response = try await conversation.sendMessage(Message(prompt))
            return response.toString
        } catch {
            throw mapped(error)
        }
        #else
        throw AssistantError.unavailable("This build was compiled without the Gemma runtime.")
        #endif
    }

    func streamReply(to prompt: String, context: AssistantContext) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                #if canImport(LiteRTLM)
                do {
                    let conversation = try await readyConversation(for: context)
                    // Chunks carry the answer so far, not deltas — mirrors how the view
                    // model upserts a single reply bubble.
                    var accumulated = ""
                    for try await chunk in conversation.sendMessageStream(Message(prompt)) {
                        accumulated += chunk.toString
                        continuation.yield(accumulated)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: mapped(error))
                }
                #else
                continuation.finish(throwing: AssistantError.unavailable("This build was compiled without the Gemma runtime."))
                #endif
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    #if canImport(LiteRTLM)
    // MARK: - Engine & conversation

    /// Returns a conversation grounded in the current receipt data, rebuilding the engine
    /// when the model file changes and the conversation when the receipt digest changes.
    private func readyConversation(for context: AssistantContext) async throws -> Conversation {
        guard let modelURL = modelManager.readyModelURL else {
            throw AssistantError.unavailable("Download the Gemma model in Settings to use this engine.")
        }

        let engine = try await readyEngine(modelURL: modelURL)

        let instructions = ReceiptAssistantPromptBuilder.instructions(for: context)
        if let conversation, conversationInstructions == instructions {
            return conversation
        }

        let conversation = try await engine.createConversation()
        // Seed the conversation with the grounding data as the first turn so every answer
        // reasons only from the user's receipts.
        _ = try await conversation.sendMessage(Message(instructions))
        self.conversation = conversation
        conversationInstructions = instructions
        return conversation
    }

    private func readyEngine(modelURL: URL) async throws -> Engine {
        if let engine, engineModelURL == modelURL {
            return engine
        }

        // Metal acceleration on real hardware. The Simulator's Metal lacks argument-buffer
        // support and caps texture bindings below what LiteRT-LM's GPU delegate needs, so it
        // fails to build the compute pipeline — fall back to CPU there so the engine still runs.
        #if targetEnvironment(simulator)
        let backend: Backend = .cpu()
        #else
        let backend: Backend = .gpu
        #endif

        let config = try EngineConfig(
            modelPath: modelURL.path,
            backend: backend,
            cacheDir: NSTemporaryDirectory()
        )
        let engine = Engine(engineConfig: config)
        try await engine.initialize()
        self.engine = engine
        engineModelURL = modelURL
        conversation = nil
        conversationInstructions = nil
        return engine
    }

    /// Turns runtime errors into user-facing `AssistantError`s so the view model's recovery
    /// path can show a friendly message and fall back to the built-in engine.
    private func mapped(_ error: Error) -> Error {
        if error is AssistantError { return error }
        if error is CancellationError { return error }
        return AssistantError.generationFailed("Gemma couldn't answer that on-device. Falling back to the built-in engine.")
    }
    #endif
}

import Foundation

#if canImport(LiteRTLM)
// See `LiteRTGemmaReceiptAssistant` for why this import is `@preconcurrency`: the package
// compiles in Swift 5 mode and carries no Sendable information, and what makes the crossing
// safe is that every call into the C handle is ordered by the main actor on this side.
@preconcurrency import LiteRTLM
#endif

/// Field extraction through Gemma 4, running on-device via LiteRT-LM.
///
/// Second in preference behind Apple Intelligence: it runs on more devices, but only once
/// the user has downloaded ~2.6 GB of weights, so it can only ever be offered rather than
/// assumed. `GemmaModelManager` owns that download and its state is the single source of
/// truth for whether this engine can run.
///
/// Unlike the assistant, extraction builds a fresh conversation for every receipt. The
/// assistant keeps one alive so the user can ask a follow-up; here a carried-over context
/// would mean the previous receipt's figures are still in the window when the next one is
/// read, which is exactly how one receipt's total ends up on another.
@MainActor
final class GemmaFieldExtractor: ReceiptFieldExtracting {
    nonisolated let engine: ReceiptExtractionEngine = .localGemma

    private let modelManager: GemmaModelManager
    private let dateExtractor = DateExtractor()

    #if canImport(LiteRTLM)
    private var runtime: Engine?
    /// URL the live engine was built from; a change means it must be rebuilt.
    private var runtimeModelURL: URL?
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
            return .unavailable(reason: "Download the Gemma model to use this engine.")
        case .downloading:
            return .unavailable(reason: "The Gemma model is still downloading.")
        case .ready:
            return .available
        }
        #else
        return .unavailable(reason: "This build was compiled without the Gemma runtime.")
        #endif
    }

    func extract(from rows: [String], currencyCode: String) async throws -> ReceiptMLExtraction? {
        #if canImport(LiteRTLM)
        guard rows.isEmpty == false, let modelURL = modelManager.readyModelURL else { return nil }

        let runtime = try await readyRuntime(modelURL: modelURL)
        let conversation = try await runtime.createConversation()

        // Instructions and receipt go in one turn. A second turn would be a second forward
        // pass over the same context for no benefit — there is no dialogue here, just one
        // question with one answer.
        let message = """
        \(ReceiptExtractionPrompt.instructions)

        Reply with a single JSON object and nothing else, using exactly these keys:
        {"merchant": string, "total": number, "subtotal": number, "tax": number, \
        "tip": number, "date": "yyyy-MM-dd"}
        Omit any key you cannot read from the receipt.

        \(ReceiptExtractionPrompt.prompt(rows: rows, currencyCode: currencyCode))
        """

        let response = try await conversation.sendMessage(Message(message))
        return ReceiptExtractionPrompt.extraction(fromJSON: response.toString, dateParser: parseDate)
        #else
        return nil
        #endif
    }

    /// Reuses the parser's own date reader rather than a second one.
    private func parseDate(_ text: String) -> Date? {
        dateExtractor.extractDate(from: [text])
    }

    #if canImport(LiteRTLM)
    /// The engine is cached across receipts even though conversations are not: loading 2.6 GB
    /// of weights is the expensive part, and it does not depend on which receipt is being read.
    private func readyRuntime(modelURL: URL) async throws -> Engine {
        if let runtime, runtimeModelURL == modelURL {
            return runtime
        }

        // Metal on real hardware; the Simulator's Metal cannot build LiteRT-LM's GPU
        // pipeline, so it runs on CPU there. Mirrors `LiteRTGemmaReceiptAssistant`.
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
        let runtime = Engine(engineConfig: config)
        try await runtime.initialize()
        self.runtime = runtime
        runtimeModelURL = modelURL
        return runtime
    }
    #endif
}

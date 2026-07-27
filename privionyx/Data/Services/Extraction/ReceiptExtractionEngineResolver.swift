import Foundation

/// Picks the best engine the device can actually run, right now.
///
/// Resolved per receipt rather than once at launch, because every input can change between
/// two scans: the user can switch Apple Intelligence on, finish a Gemma download, or delete
/// the weights to reclaim disk. Caching the decision would mean the app keeps using the
/// engine that was best the last time it asked.
@MainActor
struct ReceiptExtractionEngineResolver {
    /// What the resolver settled on, and what it could offer if the user wanted better.
    struct Resolution {
        let engine: ReceiptExtractionEngine
        /// The extractor to run, or `nil` when the answer is "just use the parser".
        let extractor: (any ReceiptFieldExtracting)?
        /// True when no model is usable but Gemma could be, if it were downloaded. This is
        /// what makes the download worth offering — and it is deliberately false when Apple
        /// Intelligence already works, since there is nothing to gain by asking for 2.6 GB.
        let canOfferGemmaDownload: Bool

        /// Whether a model is sitting ready to run. Distinct from "a model was used": the
        /// user is asked before it runs, so readiness and use are separate facts.
        var modelIsReady: Bool { extractor != nil }
    }

    private let appleIntelligence: any ReceiptFieldExtracting
    private let gemma: any ReceiptFieldExtracting
    private let modelManager: GemmaModelManager

    init(
        appleIntelligence: any ReceiptFieldExtracting = FoundationModelsFieldExtractor(),
        gemma: any ReceiptFieldExtracting = GemmaFieldExtractor(),
        modelManager: GemmaModelManager = .shared
    ) {
        self.appleIntelligence = appleIntelligence
        self.gemma = gemma
        self.modelManager = modelManager
    }

    func resolve() async -> Resolution {
        if await appleIntelligence.availability().isAvailable {
            return Resolution(engine: .appleIntelligence, extractor: appleIntelligence, canOfferGemmaDownload: false)
        }

        if await gemma.availability().isAvailable {
            return Resolution(engine: .localGemma, extractor: gemma, canOfferGemmaDownload: false)
        }

        return Resolution(
            engine: .rules,
            extractor: nil,
            canOfferGemmaDownload: gemmaIsDownloadable
        )
    }

    /// Whether Gemma is a real possibility on this device as opposed to a dead end. A device
    /// without the memory to load the weights, or a build without the runtime linked, must
    /// never be asked to spend 2.6 GB finding that out.
    private var gemmaIsDownloadable: Bool {
        #if canImport(LiteRTLM)
        switch modelManager.state {
        case .notDownloaded, .failed:
            return true
        case .unsupported, .downloading, .ready:
            return false
        }
        #else
        return false
        #endif
    }
}

import Foundation
import Testing
@testable import privionyx

/// Covers the parts of model-backed extraction that do not need a model: which engine gets
/// picked, and what happens to the parser's fields once one answers.
///
/// The engines themselves cannot be exercised here — Apple Intelligence is not available to
/// the Simulator and Gemma needs 2.6 GB of weights on disk — so everything they are asked
/// to do is behind `ReceiptFieldExtracting`, and these fakes stand in for it.
@Suite("Model-backed extraction")
struct ReceiptExtractionEngineTests {
    // MARK: - Engine selection

    @Test("Apple Intelligence wins when it is available")
    func prefersAppleIntelligence() async {
        let resolver = ReceiptExtractionEngineResolver(
            appleIntelligence: FakeExtractor(engine: .appleIntelligence, availability: .available),
            gemma: FakeExtractor(engine: .localGemma, availability: .available)
        )

        let resolution = await resolver.resolve()

        #expect(resolution.engine == .appleIntelligence)
        #expect(resolution.canOfferGemmaDownload == false)
    }

    @Test("Gemma is used when Apple Intelligence cannot run")
    func fallsBackToGemma() async {
        let resolver = ReceiptExtractionEngineResolver(
            appleIntelligence: FakeExtractor(engine: .appleIntelligence, availability: .unavailable(reason: "no")),
            gemma: FakeExtractor(engine: .localGemma, availability: .available)
        )

        let resolution = await resolver.resolve()

        #expect(resolution.engine == .localGemma)
        // Nothing to offer: the weights are already here.
        #expect(resolution.canOfferGemmaDownload == false)
    }

    @Test("Neither model available falls back to the parser and offers nothing to run")
    func fallsBackToRules() async {
        let resolver = ReceiptExtractionEngineResolver(
            appleIntelligence: FakeExtractor(engine: .appleIntelligence, availability: .unavailable(reason: "no")),
            gemma: FakeExtractor(engine: .localGemma, availability: .unavailable(reason: "not downloaded"))
        )

        let resolution = await resolver.resolve()

        #expect(resolution.engine == .rules)
        #expect(resolution.extractor == nil)
    }

    // MARK: - When the user is and is not interrupted

    /// The rule that matters most here: an installed model is never asked about. Using it
    /// costs the user nothing and sends nothing anywhere, so a prompt would carry no decision.
    @Test("An installed model runs without asking")
    func readyModelRunsWithoutAsking() {
        let decision = ReceiptExtractionConsentPolicy.decide(
            modelIsReady: true,
            gemmaIsDownloadable: false,
            consent: .useModelWhenAvailable,
            downloadPromptSuppressed: false
        )

        #expect(decision == .useModel)
    }

    /// Even when the download offer has been silenced, an installed model still just runs —
    /// the two settings are about different things.
    @Test("A suppressed download prompt does not stop an installed model running")
    func suppressedDownloadDoesNotDisableAReadyModel() {
        let decision = ReceiptExtractionConsentPolicy.decide(
            modelIsReady: true,
            gemmaIsDownloadable: false,
            consent: .useModelWhenAvailable,
            downloadPromptSuppressed: true
        )

        #expect(decision == .useModel)
    }

    @Test("With no model installed, the download is offered")
    func offersTheDownload() {
        let decision = ReceiptExtractionConsentPolicy.decide(
            modelIsReady: false,
            gemmaIsDownloadable: true,
            consent: .useModelWhenAvailable,
            downloadPromptSuppressed: false
        )

        #expect(decision == .askToDownloadGemma)
    }

    @Test("A declined download offer is not shown again")
    func suppressedDownloadPromptStaysSuppressed() {
        let decision = ReceiptExtractionConsentPolicy.decide(
            modelIsReady: false,
            gemmaIsDownloadable: true,
            consent: .useModelWhenAvailable,
            downloadPromptSuppressed: true
        )

        #expect(decision == .useBuiltIn)
    }

    /// Someone who has switched models off is not waiting to be sold 2.6 GB of one.
    @Test("Always-built-in silences the download offer too")
    func alwaysBuiltInSilencesEverything() {
        let decision = ReceiptExtractionConsentPolicy.decide(
            modelIsReady: false,
            gemmaIsDownloadable: true,
            consent: .alwaysUseBuiltIn,
            downloadPromptSuppressed: false
        )

        #expect(decision == .useBuiltIn)
    }

    @Test("Always-built-in refuses an installed model as well")
    func alwaysBuiltInRefusesAReadyModel() {
        let decision = ReceiptExtractionConsentPolicy.decide(
            modelIsReady: true,
            gemmaIsDownloadable: false,
            consent: .alwaysUseBuiltIn,
            downloadPromptSuppressed: false
        )

        #expect(decision == .useBuiltIn)
    }

    @Test("Nothing to run and nothing to download proceeds without interrupting")
    func noOptionsMeansNoPrompt() {
        let decision = ReceiptExtractionConsentPolicy.decide(
            modelIsReady: false,
            gemmaIsDownloadable: false,
            consent: .useModelWhenAvailable,
            downloadPromptSuppressed: false
        )

        #expect(decision == .useBuiltIn)
    }

    // MARK: - Merging a model's answer over the parser's

    @Test("A model's figures replace the parser's")
    func modelOverridesParser() {
        let parsed = Self.parsed(merchant: "ALE", amount: 129.09, subtotal: nil, tax: nil)
        let extraction = ReceiptMLExtraction(
            merchant: "Old Navy", amount: 50.69, subtotal: 44.86, tax: 5.83, tip: nil, date: nil
        )

        let result = extraction.applied(to: parsed)

        #expect(result.merchant == "Old Navy")
        #expect(result.amount == 50.69)
        #expect(result.subtotal == 44.86)
        #expect(result.tax == 5.83)
    }

    /// The failure this guards against is a better engine returning *less* data than a worse
    /// one: a model that reads only the total must not blank the merchant the parser found.
    @Test("Fields the model leaves empty keep the parser's values")
    func modelSilenceDoesNotErase() {
        let parsed = Self.parsed(merchant: "Lindt", amount: 42.00, subtotal: 36.54, tax: 4.75)
        let extraction = ReceiptMLExtraction(
            merchant: nil, amount: 41.29, subtotal: nil, tax: nil, tip: nil, date: nil
        )

        let result = extraction.applied(to: parsed)

        #expect(result.amount == 41.29)
        #expect(result.merchant == "Lindt")
        #expect(result.subtotal == 36.54)
        #expect(result.tax == 4.75)
    }

    /// Nothing checks the model's arithmetic, so a reconciliation verdict earned by the
    /// parser's figures must not be left standing over figures it never saw.
    @Test("Overriding a total withdraws the reconciler's verdict")
    func overridingClearsTotalsStatus() {
        var parsed = Self.parsed(merchant: "Lindt", amount: 42.00, subtotal: 36.54, tax: 4.75)
        parsed.totalsStatus = .consistent
        parsed.derivedTotals = [.subtotal]

        let result = ReceiptMLExtraction(
            merchant: nil, amount: 41.29, subtotal: nil, tax: nil, tip: nil, date: nil
        ).applied(to: parsed)

        #expect(result.totalsStatus == .unverified)
        #expect(result.derivedTotals.isEmpty)
    }

    @Test("A merchant-only answer leaves the totals verdict alone")
    func merchantOnlyKeepsTotalsStatus() {
        var parsed = Self.parsed(merchant: "ALE", amount: 50.69, subtotal: 44.86, tax: 5.83)
        parsed.totalsStatus = .consistent

        let result = ReceiptMLExtraction(
            merchant: "Old Navy", amount: nil, subtotal: nil, tax: nil, tip: nil, date: nil
        ).applied(to: parsed)

        #expect(result.merchant == "Old Navy")
        #expect(result.totalsStatus == .consistent)
    }

    // MARK: - Reading what a text-completion engine returns

    @Test("JSON wrapped in prose and fences is still read")
    func readsFencedJSON() {
        let reply = """
        Sure! Here are the fields:
        ```json
        {"merchant": "IKEA", "total": 11.50, "subtotal": 10.18, "tax": 1.32}
        ```
        """

        let extraction = ReceiptExtractionPrompt.extraction(fromJSON: reply) { _ in nil }

        #expect(extraction?.merchant == "IKEA")
        #expect(extraction?.amount == 11.50)
        #expect(extraction?.subtotal == 10.18)
    }

    @Test("Currency symbols and comma decimals are read as numbers")
    func readsFormattedNumbers() {
        let reply = #"{"merchant": "Lindt", "total": "$41.29", "tax": "4,75"}"#

        let extraction = ReceiptExtractionPrompt.extraction(fromJSON: reply) { _ in nil }

        #expect(extraction?.amount == 41.29)
        #expect(extraction?.tax == 4.75)
    }

    /// A model asked for a field it cannot fill often answers in words. Those answers must
    /// not reach the draft as the shop's name.
    @Test("A model saying it does not know is not a merchant name")
    func refusalIsNotAMerchant() {
        let reply = #"{"merchant": "Unknown", "total": 12.00}"#

        let extraction = ReceiptExtractionPrompt.extraction(fromJSON: reply) { _ in nil }

        #expect(extraction?.merchant == nil)
        #expect(extraction?.amount == 12.00)
    }

    @Test("A reply with no JSON at all yields nothing rather than empty fields")
    func nonJSONReplyYieldsNil() {
        let extraction = ReceiptExtractionPrompt.extraction(
            fromJSON: "I couldn't read that receipt, sorry."
        ) { _ in nil }

        #expect(extraction == nil)
    }

    // MARK: - Helpers

    private static func parsed(
        merchant: String,
        amount: Double,
        subtotal: Double?,
        tax: Double?
    ) -> ParsedReceiptData {
        ParsedReceiptData(
            merchant: merchant,
            amount: amount,
            subtotal: subtotal,
            tax: tax,
            tip: nil,
            date: .now,
            category: .shopping,
            rawText: "",
            lineItems: [],
            notes: ""
        )
    }
}

@MainActor
private final class FakeExtractor: ReceiptFieldExtracting {
    nonisolated let engine: ReceiptExtractionEngine
    private let stubbedAvailability: AssistantAvailability
    private let stubbedResult: ReceiptMLExtraction?

    init(
        engine: ReceiptExtractionEngine,
        availability: AssistantAvailability,
        result: ReceiptMLExtraction? = nil
    ) {
        self.engine = engine
        self.stubbedAvailability = availability
        self.stubbedResult = result
    }

    func availability() async -> AssistantAvailability { stubbedAvailability }

    func extract(from rows: [String], currencyCode: String) async throws -> ReceiptMLExtraction? {
        stubbedResult
    }
}

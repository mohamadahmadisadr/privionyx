import Foundation
import Testing
@testable import privionyx

@Suite("Gemma model selection")
struct GemmaModelCatalogTests {
    private let sixGB: UInt64 = 6 * 1_073_741_824
    private let fourGB: UInt64 = 4 * 1_073_741_824
    private let sixteenGB: UInt64 = 16 * 1_073_741_824

    @Test("A device at the memory floor gets the E2B model")
    func atFloorIsSupported() {
        let spec = GemmaModelCatalog.modelForCurrentDevice(physicalMemory: sixGB)
        #expect(spec?.id == GemmaModelSpec.gemma4E2B.id)
    }

    @Test("A high-memory device gets a supported model")
    func highMemoryIsSupported() {
        #expect(GemmaModelCatalog.modelForCurrentDevice(physicalMemory: sixteenGB) != nil)
    }

    @Test("A device below the floor is unsupported")
    func belowFloorIsUnsupported() {
        #expect(GemmaModelCatalog.modelForCurrentDevice(physicalMemory: fourGB) == nil)
    }

    @Test("The E2B spec points at the ungated LiteRT-LM file")
    func specPointsAtExpectedFile() {
        let spec = GemmaModelSpec.gemma4E2B
        #expect(spec.filename == "gemma-4-E2B-it.litertlm")
        #expect(spec.remoteURL.absoluteString.contains("litert-community/gemma-4-E2B-it-litert-lm"))
        #expect(spec.remoteURL.absoluteString.hasSuffix("gemma-4-E2B-it.litertlm?download=true"))
    }

    @Test("Size description is human-readable")
    func sizeDescriptionIsFriendly() {
        let text = GemmaModelCatalog.sizeDescription(for: .gemma4E2B)
        #expect(text.contains("GB"))
    }

    /// The system hands the app a completion handler for *any* background session it is
    /// woken for, and expects it back whether or not the app recognises the identifier.
    /// Dropping it holds the app's background assertion open until it is killed.
    @MainActor
    @Test("An unrecognised background session identifier still returns its completion handler")
    func foreignSessionIdentifierIsAcknowledged() async {
        await confirmation("completion handler called") { called in
            GemmaModelManager.handleBackgroundSessionEvents(
                identifier: "com.example.somebody-elses-session"
            ) {
                called()
            }
        }
    }
}

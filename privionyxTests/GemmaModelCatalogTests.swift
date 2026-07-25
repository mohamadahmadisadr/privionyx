import Foundation
import Testing
@testable import privionyx

@Suite("Gemma model selection")
struct GemmaModelCatalogTests {
    /// Figures as `ProcessInfo.physicalMemory` reports them, not as devices are marketed.
    ///
    /// The distinction is the whole point of this suite. It previously fed the floor its own
    /// constant back — `6 * 1_073_741_824` against a floor of `6 * 1_073_741_824` — which is
    /// an arithmetic identity rather than a device, and it passed while every real phone of
    /// that tier was turned away.
    @Test("A device that can run the model is offered it", arguments: [
        // 6 GB tier: iPhone 15, 15 Plus, 14 Pro, 13 Pro.
        5_500_000_000 as UInt64,
        5_900_000_000,
        // 8 GB tier: iPhone 15 Pro and later.
        7_900_000_000,
        16_000_000_000
    ])
    func supportedDeviceGetsModel(physicalMemory: UInt64) {
        let spec = GemmaModelCatalog.modelForCurrentDevice(physicalMemory: physicalMemory)
        #expect(spec?.id == GemmaModelSpec.gemma4E2B.id)
    }

    @Test("A device that cannot run the model is not offered it", arguments: [
        // 4 GB tier: iPhone 12, 13, 14, SE. The upper figure is what a 4 GB device reports
        // when it reserves almost nothing, and it still has to fall below the floor.
        3_700_000_000 as UInt64,
        4_000_000_000,
        3_000_000_000
    ])
    func unsupportedDeviceGetsNothing(physicalMemory: UInt64) {
        #expect(GemmaModelCatalog.modelForCurrentDevice(physicalMemory: physicalMemory) == nil)
    }

    /// A floor written in binary gigabytes is unreachable by the tier it names: 6 GiB is
    /// 6.44 GB in decimal, which is more RAM than a "6 GB" phone contains. This is the
    /// mistake that made the whole tier unsupported, so it is worth stating outright.
    @Test("The floor is reachable by the smallest tier it admits")
    func floorIsBelowNominalSixGigabytes() throws {
        let floor = try #require(GemmaModelCatalog.lowestMemoryFloor)

        #expect(floor < 6_000_000_000, "a 6 GB device can never report 6 GB or more")
    }

    @Test("The reported memory is shown exactly, not only rounded")
    func memoryDescriptionCarriesTheByteCount() {
        let text = GemmaModelCatalog.memoryDescription(5_500_000_000)

        // The rounded figure is what makes it readable; the byte count is what makes a
        // wrong verdict diagnosable. Compared without separators, which are the reader's
        // locale's business rather than this test's.
        #expect(text.filter(\.isNumber).contains("5500000000"))
        #expect(text.contains("GB"))
    }

    @Test("The E2B spec points at the ungated LiteRT-LM file")
    func specPointsAtExpectedFile() {
        let spec = GemmaModelSpec.gemma4E2B
        #expect(spec.filename == "gemma-4-E2B-it.litertlm")
        #expect(spec.remoteURL.absoluteString.contains("litert-community/gemma-4-E2B-it-litert-lm"))
        #expect(spec.remoteURL.absoluteString.hasSuffix("gemma-4-E2B-it.litertlm?download=true"))
    }

    /// A digest describes one set of bytes. Pointing at a branch would let the repository push
    /// a new build and turn every download from that moment on into a verification failure —
    /// a shipped app breaking because somebody else committed.
    @Test("The download URL is pinned to a revision rather than a branch")
    func specPinsARevision() throws {
        let url = GemmaModelSpec.gemma4E2B.remoteURL.absoluteString
        let revision = try #require(
            url.components(separatedBy: "/resolve/").last?.components(separatedBy: "/").first
        )

        let isHex = revision.allSatisfy(\.isHexDigit)

        #expect(revision != "main")
        #expect(revision.count == 40, "expected a full commit hash, got \(revision)")
        #expect(isHex)
    }

    @Test("The E2B spec carries a full SHA-256")
    func specCarriesADigest() {
        let digest = GemmaModelSpec.gemma4E2B.sha256
        let isLowerHex = digest.allSatisfy { $0.isHexDigit && $0.isUppercase == false }

        #expect(digest.count == 64)
        #expect(isLowerHex)
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

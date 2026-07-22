import Foundation
import Testing
@testable import privionyx

/// The learning loop: a name the user fixes once should not have to be fixed again.
@Suite("Merchant corrections")
struct MerchantLearningTests {
    private func makeService() -> MerchantRuleService {
        let defaults = UserDefaults(suiteName: "privionyx.tests.\(UUID().uuidString)")!
        return MerchantRuleService(defaults: defaults)
    }

    /// The case this exists for: the device read "Angler SF" as "Angler Sr", and the same
    /// letterhead in the same font will read the same way next time.
    @Test("A corrected name is applied to the next identical misreading")
    func correctionIsRemembered() {
        let service = makeService()
        service.saveMerchantCorrection(recognized: "Angler Sr", corrected: "Angler SF")

        #expect(service.correctedMerchantName(forRecognized: "Angler Sr") == "Angler SF")
        // Recognition varies in case and punctuation between scans; the lookup should not.
        #expect(service.correctedMerchantName(forRecognized: "ANGLER SR") == "Angler SF")
    }

    @Test("An unrelated merchant is unaffected")
    func correctionDoesNotLeak() {
        let service = makeService()
        service.saveMerchantCorrection(recognized: "Angler Sr", corrected: "Angler SF")

        #expect(service.correctedMerchantName(forRecognized: "Costco") == nil)
    }

    /// Restyling what was already read correctly teaches nothing and would fill storage with
    /// entries that change no outcome.
    @Test("Restyling the same name is not stored as a correction")
    func restylingIsNotLearned() {
        let service = makeService()
        service.saveMerchantCorrection(recognized: "COSTCO", corrected: "Costco")

        #expect(service.correctedMerchantName(forRecognized: "COSTCO") == nil)
    }

    @Test("A failed extraction is not learned from")
    func unknownMerchantIsNotLearned() {
        let service = makeService()
        service.saveMerchantCorrection(recognized: "Unknown Merchant", corrected: "Angler SF")

        #expect(service.correctedMerchantName(forRecognized: "Unknown Merchant") == nil)
    }

    @Test("The use case leaves an unseen merchant alone")
    func useCasePassesThroughUnknownNames() {
        let service = makeService()
        let useCase = ResolveMerchantUseCase(merchantRules: service)

        #expect(useCase.execute(recognized: "Tim Hortons") == "Tim Hortons")

        service.saveMerchantCorrection(recognized: "Tim Hortons", corrected: "Tim Hortons Cafe")
        #expect(useCase.execute(recognized: "Tim Hortons") == "Tim Hortons Cafe")
    }
}

import Foundation
import Testing
@testable import privionyx

/// The letterhead is where a merchant name normally lives, and reading anywhere else lets a
/// payment network or a survey URL outrank the real thing. A terminal-printed slip breaks that
/// assumption: its top lines are the terminal's own boilerplate and the shop is named once, in
/// the closing sign-off.
///
/// These cover the fallback that reads the sign-off and, just as much, the cases where it has
/// to stay silent. An invented merchant is worse than none.
@Suite("Merchant extraction")
struct MerchantExtractorTests {
    private let extractor = MerchantExtractor()

    /// A terminal slip with nothing but boilerplate above the fold. `closing` is everything
    /// printed under the payment line, which is the part each test varies.
    private func terminalSlip(closing: [String]) -> [String] {
        [
            "MERCHANT COPY",
            "TERM ID 44012",
            "BATCH 0091",
            "TOPSOIL 25L X3 41.97",
            "CEDAR MULCH 12.99",
            "SUBTOTAL 54.96",
            "HST 13% 7.14",
            "TOTAL 62.10"
        ] + closing
    }

    @Test("A name in the sign-off is found when the letterhead has none")
    func signOffName() {
        let lines = terminalSlip(closing: [
            "THANK YOU FOR SHOPPING AT",
            "LAKEVIEW GARDEN CENTRE",
            "03/07/2026 10:52"
        ])
        #expect(extractor.extractMerchant(from: lines) == "LAKEVIEW GARDEN CENTRE")
    }

    @Test("A merchant copy banner is not the merchant")
    func merchantCopyBannerRejected() {
        // Upper-case, short and first — everything the position heuristic rewards.
        #expect(extractor.extractMerchant(from: terminalSlip(closing: [])) == nil)
    }

    @Test("A sign-off that names nobody invents nobody")
    func plainSignOffYieldsNothing() {
        // "THANK YOU" is a whole sentence. What follows it is a slogan, not a vendor.
        let lines = terminalSlip(closing: [
            "THANK YOU",
            "PLEASE COME AGAIN",
            "03/07/2026 10:52"
        ])
        #expect(extractor.extractMerchant(from: lines) == nil)
    }

    @Test("Terminal boilerplate under a sign-off is not read as a name")
    func boilerplateAfterSignOffRejected() {
        let lines = terminalSlip(closing: [
            "THANK YOU FOR SHOPPING AT",
            "INTERAC CHIP",
            "APPROVED"
        ])
        #expect(extractor.extractMerchant(from: lines) == nil)
    }

    @Test("A letterhead name still wins over anything in the footer")
    func letterheadWinsOverFooter() {
        let lines = [
            "NORTHSIDE HARDWARE",
            "TOTAL 20.00",
            "THANK YOU FOR SHOPPING AT",
            "PARTICIPATING LOCATIONS"
        ]
        #expect(extractor.extractMerchant(from: lines) == "NORTHSIDE HARDWARE")
    }
}

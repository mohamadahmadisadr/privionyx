import Foundation
import Testing
@testable import privionyx

/// The item name shown to the user, as opposed to the item sum, which is tested through the
/// corpus. Sums are unaffected by naming; these guard only what is displayed.
@Suite("Line item names")
struct LineItemNameTests {
    @Test("Leading tax class, code and quantity are peeled off")
    func leadingNoiseRemoved() {
        #expect(LineItemExtractor.cleanedItemName("E 577 MPEPSI COLA") == "MPEPSI COLA")
        #expect(LineItemExtractor.cleanedItemName("E 692731 KS ORG EVOO") == "KS ORG EVOO")
        #expect(LineItemExtractor.cleanedItemName("1216/15 CRES SCOPE") == "CRES SCOPE")
        #expect(LineItemExtractor.cleanedItemName("E 3 WHOLE MILK") == "WHOLE MILK")
        #expect(LineItemExtractor.cleanedItemName("46750 BEEF SALAMI") == "BEEF SALAMI")
    }

    @Test("A clean name is left untouched")
    func cleanNameUnchanged() {
        #expect(LineItemExtractor.cleanedItemName("KS FAB SOFT") == "KS FAB SOFT")
        #expect(LineItemExtractor.cleanedItemName("BANANAS LOOSE") == "BANANAS LOOSE")
    }

    /// Peeling stops at the last token that still holds a name, so a genuine short lead is
    /// not consumed down to nothing.
    @Test("Peeling never consumes the whole name")
    func peelingStopsAtTheName() {
        #expect(LineItemExtractor.cleanedItemName("E 100 MILK") == "MILK")
        // Only bookkeeping and no real name: rejected rather than returned empty.
        #expect(LineItemExtractor.cleanedItemName("E 577 12") == nil)
    }

    @Test("Recognition errors in the name are left alone")
    func recognitionErrorsUntouched() {
        // "MPEPSI" is a misread of "PEPSI"; correcting it would invent content.
        #expect(LineItemExtractor.cleanedItemName("MPEPSI COLA") == "MPEPSI COLA")
    }
}

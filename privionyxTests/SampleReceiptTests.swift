import Foundation
import Testing
@testable import privionyx

/// Sample receipts are ordinary receipts — they count towards the dashboard, the budgets and
/// the recurring-charge detection exactly as real ones do, which is what makes them useful to
/// someone evaluating the app and what makes them dangerous to someone already using it.
///
/// The tag is the whole safety mechanism. These tests are about the property that matters: that
/// removing samples takes back precisely what was added, and never a receipt the user entered.
@MainActor
@Suite("Sample receipts")
struct SampleReceiptTests {
    private func makeAppState() -> PrivionyxAppState {
        PrivionyxAppState(container: .preview)
    }

    private func realReceipt(merchant: String, tags: [String] = []) -> ReceiptDraft {
        ReceiptDraft(
            merchant: merchant,
            amount: 12.34,
            subtotal: nil,
            tax: nil,
            tip: nil,
            date: .now,
            category: .grocery,
            customCategoryName: nil,
            tags: tags,
            imageData: nil,
            rawText: nil,
            lineItems: [],
            notes: "",
            status: .reviewed
        )
    }

    @Test("Nothing is loaded until it is asked for")
    func nothingLoadsOnItsOwn() async {
        let appState = makeAppState()

        await appState.bootstrapIfNeeded()

        #expect(appState.receipts.isEmpty)
        #expect(appState.hasSampleReceipts == false)
    }

    @Test("Every sample carries the tag")
    func samplesAreTagged() async throws {
        let appState = makeAppState()
        await appState.bootstrapIfNeeded()

        try await appState.loadSampleReceipts()

        #expect(appState.receipts.isEmpty == false)
        #expect(appState.receipts.allSatisfy { $0.tags.contains(PrivionyxSampleData.tag) })
        #expect(appState.hasSampleReceipts)
    }

    @Test("Removing samples leaves the user's own receipts alone")
    func removalSparesRealReceipts() async throws {
        let appState = makeAppState()
        await appState.bootstrapIfNeeded()
        try await appState.loadSampleReceipts()
        try await appState.saveReceipt(realReceipt(merchant: "Corner Store"))
        try await appState.saveReceipt(realReceipt(merchant: "Hardware Depot", tags: ["Work"]))

        try await appState.removeSampleReceipts()

        #expect(appState.receipts.map(\.merchant).sorted() == ["Corner Store", "Hardware Depot"])
        #expect(appState.hasSampleReceipts == false)
    }

    /// A sample the user edited into something they want to keep is theirs. Dropping the tag in
    /// the editor is what says so, and removal has to honour it — otherwise "remove samples"
    /// silently deletes a receipt someone had adopted.
    @Test("A sample the user has untagged is no longer a sample")
    func untaggedSampleSurvivesRemoval() async throws {
        let appState = makeAppState()
        await appState.bootstrapIfNeeded()
        try await appState.loadSampleReceipts()

        let adopted = try #require(appState.receipts.first)
        var edited = ReceiptDraft(item: adopted)
        edited.tags = []
        try await appState.saveReceipt(edited)

        try await appState.removeSampleReceipts()

        #expect(appState.receipts.map(\.id) == [adopted.id])
        #expect(appState.hasSampleReceipts == false)
    }

    @Test("Removing samples when there are none is not an error")
    func removalWithNoSamplesIsHarmless() async throws {
        let appState = makeAppState()
        await appState.bootstrapIfNeeded()
        try await appState.saveReceipt(realReceipt(merchant: "Corner Store"))

        try await appState.removeSampleReceipts()

        #expect(appState.receipts.count == 1)
    }

    @Test("Samples span categories and dates, so the dashboard has something to show")
    func samplesAreVaried() {
        let drafts = PrivionyxSampleData.drafts()
        let categories = Set(drafts.map(\.category))
        let dates = Set(drafts.map(\.date))

        #expect(drafts.count >= 5)
        #expect(categories.count >= 4, "a single-category library exercises no breakdown")
        #expect(dates.count >= 4, "receipts all on one day exercise no trend")
    }
}

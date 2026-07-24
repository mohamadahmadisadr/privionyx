import Foundation
import Testing
@testable import privionyx

/// Reproduces "receipts vanish after the app is closed and reopened".
///
/// A relaunch is a brand-new `CoreDataStack` reading the same on-disk SQLite file. This
/// saves through one stack, throws it away, opens a second stack at the same store URL, and
/// checks the receipt survived — exactly what the app does across launches.
@Suite("Persistence round trip")
struct PersistenceRoundTripTests {
    @Test("A saved receipt is present after opening a fresh stack")
    func savedReceiptSurvivesRelaunch() async throws {
        let marker = "RoundTrip-\(UUID().uuidString)"
        let draft = ReceiptDraft(
            merchant: marker,
            amount: 42.50,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            category: .shopping,
            notes: "round trip",
            status: .reviewed
        )

        // First launch: save.
        let firstStack = CoreDataStack(inMemory: false)
        let firstRepo = CoreDataReceiptRepository(stack: firstStack)
        try await firstRepo.upsertReceipt(draft)

        // Second launch: brand-new stack over the same on-disk store.
        let secondStack = CoreDataStack(inMemory: false)
        let secondRepo = CoreDataReceiptRepository(stack: secondStack)
        let fetched = try await secondRepo.fetchReceipts(matching: nil)

        let survivor = fetched.first { $0.merchant == marker }

        // Clean up before asserting, so a failure doesn't leave test junk in the store.
        if let survivor {
            try? await secondRepo.deleteReceipt(id: survivor.id)
        } else {
            try? await secondRepo.deleteReceipt(id: draft.id)
        }

        #expect(survivor != nil, "receipt saved in the first stack was gone from a fresh stack")
        #expect(survivor?.amount == 42.50)
    }

    /// The full app path a relaunch actually runs: save through PrivionyxAppState, then a
    /// brand-new container + state that bootstraps (purge legacy seed, then load). If the
    /// receipt is missing here but present in the raw round trip above, the fault is in the
    /// orchestration (purge / load), not the store.
    @MainActor
    @Test("A saved receipt is loaded by a fresh app state on launch")
    func savedReceiptLoadedByFreshAppState() async throws {
        let marker = "AppState-\(UUID().uuidString)"
        // Attach image data so the save exercises ReceiptFileStorage, exactly as the real
        // Save button does (previewImage.jpegData) — the path the raw round trip skipped.
        let draft = ReceiptDraft(
            merchant: marker,
            amount: 17.99,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            category: .shopping,
            imageData: Data(repeating: 0xAB, count: 2_048),
            notes: "app state round trip",
            status: .reviewed
        )

        // First launch: save through the app state, same as the Save button does.
        let firstState = PrivionyxAppState(container: .live())
        try await firstState.saveReceipt(draft)

        // Second launch: fresh container + state, running the real bootstrap.
        let secondState = PrivionyxAppState(container: .live())
        await secondState.bootstrapIfNeeded()

        let survivor = secondState.receipts.first { $0.merchant == marker }

        // The detail screen reads the image on demand through the store, so that is where
        // the round trip has to be checked. Resolved against the second container to prove
        // the stored path still resolves after a relaunch.
        let storedImage = survivor.flatMap {
            secondState.container.imageStore.loadImageData(at: $0.imagePath)
        }

        if let survivor {
            try? await secondState.deleteReceipt(id: survivor.id)
        } else {
            try? await PrivionyxAppContainer.live().deleteReceiptUseCase.execute(id: draft.id)
        }

        #expect(survivor != nil, "receipt was saved but a fresh app state did not load it on launch")
        #expect(survivor?.hasImage == true, "receipt loaded but carries no image path")
        #expect(storedImage != nil, "receipt loaded but its image did not round trip")
        #expect(storedImage?.count == 2_048)
    }
}

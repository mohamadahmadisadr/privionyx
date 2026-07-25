import Foundation
import Testing
@testable import privionyx

/// Turning a thrown error into something worth showing someone.
@Suite("User-facing errors")
struct UserFacingErrorTests {
    /// The distinction the type exists for: our own errors carry sentences, Foundation's
    /// carry codes, and only the first should reach the alert verbatim.
    @Test("An error we wrote keeps its own message")
    func authoredMessageIsKept() {
        let error = UserFacingError.readingReceipt(OCRServiceError.unsupportedImage)

        #expect(error.message == OCRServiceError.unsupportedImage.errorDescription)
    }

    @Test("A Cocoa error never reaches the user")
    func cocoaErrorIsReplaced() {
        // The shape of a Core Data save failure: localizedDescription here is
        // "The operation couldn't be completed. (NSCocoaErrorDomain error 133020.)"
        let cocoa = NSError(domain: NSCocoaErrorDomain, code: 133_020)
        let error = UserFacingError.savingReceipt(cocoa)

        #expect(error.message.contains("133020") == false)
        #expect(error.message.contains("Cocoa") == false)
        #expect(error.message.isEmpty == false)
    }

    @Test("Running out of space is named, because the user can act on it")
    func outOfSpaceIsNamed() {
        let full = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        let error = UserFacingError.savingReceipt(full)

        #expect(error.title == "Not enough space")
        #expect(error.message.localizedCaseInsensitiveContains("free up"))
    }

    @Test("A failed save says the entry is not lost")
    func failedSaveReassures() {
        let error = UserFacingError.savingReceipt(NSError(domain: NSCocoaErrorDomain, code: 133_020))

        // The form is still populated behind the alert, and saying so is the difference
        // between retrying and retyping.
        #expect(error.message.localizedCaseInsensitiveContains("try again"))
    }

    @Test("Every operation produces a non-empty title and message", arguments: [
        UserFacingError.loadingReceipts(NSError(domain: NSCocoaErrorDomain, code: 1)),
        UserFacingError.savingReceipt(NSError(domain: NSCocoaErrorDomain, code: 1)),
        UserFacingError.deletingReceipt(NSError(domain: NSCocoaErrorDomain, code: 1)),
        UserFacingError.readingReceipt(NSError(domain: NSCocoaErrorDomain, code: 1)),
        UserFacingError.scanningUnsupported,
        UserFacingError.incompleteReceipt,
        UserFacingError.storeUnavailable("The database was reset.")
    ])
    func alwaysPresentable(error: UserFacingError) {
        #expect(error.title.isEmpty == false)
        #expect(error.message.isEmpty == false)
        // A title is a heading, not a sentence — anything long belongs in the message.
        #expect(error.title.count < 40, "title too long to head an alert: \(error.title)")
    }

    @Test("Distinct failures are distinguishable")
    func failuresAreDistinct() {
        let saving = UserFacingError.savingReceipt(NSError(domain: NSCocoaErrorDomain, code: 1))
        let loading = UserFacingError.loadingReceipts(NSError(domain: NSCocoaErrorDomain, code: 1))

        // The whole complaint about the previous single string was that these looked alike.
        #expect(saving != loading)
    }
}

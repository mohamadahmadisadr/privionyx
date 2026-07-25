import Foundation

/// A failure as the user should meet it: what went wrong in their terms, and where possible
/// what to do about it.
///
/// Everything used to reach the alert as `error.localizedDescription`, which is fine for the
/// error types this app writes and useless for the ones it merely propagates — a Core Data
/// or FileManager failure reads as "The operation couldn't be completed. (Cocoa error
/// 133020.)". A disk-full save and a corrupt store were indistinguishable, and neither
/// suggested an action.
nonisolated struct UserFacingError: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let message: String

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.message == rhs.message
    }
}

// MARK: - Operations

nonisolated extension UserFacingError {
    static func loadingReceipts(_ error: Error) -> Self {
        Self(
            title: "Couldn't load your receipts",
            message: authored(error) ?? "Something went wrong reading your saved receipts. Reopening the app usually clears it."
        )
    }

    static func savingReceipt(_ error: Error) -> Self {
        if isOutOfSpace(error) {
            return Self(
                title: "Not enough space",
                message: "There isn't enough free space to save this receipt and its photo. Free up some space and try saving again — nothing you've typed will be lost."
            )
        }

        return Self(
            title: "Couldn't save receipt",
            message: authored(error) ?? "The receipt wasn't saved. Your entry is still here, so you can try again."
        )
    }

    static func deletingReceipt(_ error: Error) -> Self {
        Self(
            title: "Couldn't delete receipt",
            message: authored(error) ?? "The receipt is still saved. Try again in a moment."
        )
    }

    /// Recognition failed on an image the user has already chosen, so the useful thing to
    /// offer is the manual path rather than an explanation.
    static func readingReceipt(_ error: Error) -> Self {
        Self(
            title: "Couldn't read that receipt",
            message: authored(error) ?? "The text couldn't be recognised. Try a straighter, better-lit photo — or enter the details yourself."
        )
    }

    static let scanningUnsupported = Self(
        title: "Scanning unavailable",
        message: "This device doesn't support document scanning. You can import a photo from your library instead."
    )

    static let incompleteReceipt = Self(
        title: "Missing details",
        message: "A merchant and an amount are needed before a receipt can be saved."
    )

    /// The stack has already composed the specific reason — it knows whether the store was
    /// reset, quarantined, or is missing entirely.
    static func storeUnavailable(_ message: String) -> Self {
        Self(title: "Database problem", message: message)
    }
}

// MARK: - Underlying causes

private nonisolated extension UserFacingError {
    /// The message from an error that was written to be read by a person.
    ///
    /// The app's own error types conform to `LocalizedError` and carry real sentences.
    /// Bridged `NSError`s — which is what Core Data and FileManager throw — do not conform,
    /// so they fall through to the operation's own copy rather than showing a code number.
    static func authored(_ error: Error) -> String? {
        (error as? LocalizedError)?.errorDescription
    }

    /// The one underlying cause worth naming on its own. It is common on a phone full of
    /// photos, and unlike most failures the user can actually do something about it.
    static func isOutOfSpace(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSCocoaErrorDomain else { return false }
        return nsError.code == NSFileWriteOutOfSpaceError
    }
}

import Foundation

/// Where the add-receipt flow has got to.
///
/// Previously a free-form `String` ("Ready", "Manual Entry", "Extracting Fields", …) that
/// the review copy switched on by value comparison, so a typo on either side of the
/// comparison was a silent behaviour change the compiler could not see. Nothing renders the
/// stage directly — it only drives decisions — so it costs nothing to make it a closed set.
enum ReceiptCaptureStage: Equatable {
    /// Nothing in flight; the capture screen is waiting for a photo or a manual entry.
    case idle
    /// The user chose to type the receipt in rather than scan it. Suppresses the advice
    /// about extraction quality, since nothing was extracted.
    case manualEntry
    /// A capture is on screen and the user is positioning the crop.
    case adjustingCrop
    /// Recognition and parsing are running.
    case extracting
    /// Parsing produced a draft and the review form is populated.
    case readyForReview
    /// Parsing failed. The form is still usable; the figures are just not filled in.
    case needsReview
    /// The draft has been written to the store.
    case saved
}

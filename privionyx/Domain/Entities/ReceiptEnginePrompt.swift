import Foundation

/// The one question put to the user before a receipt is read.
///
/// There used to be a second — "may I use the model already installed?" — and it was not
/// worth asking: an on-device model costs nothing to use and sends nothing anywhere, so the
/// prompt had no decision behind it. What remains is the only genuine commitment, which is
/// fetching the weights in the first place.
struct GemmaDownloadPrompt: Identifiable, Equatable {
    /// Human-readable download size, e.g. "2.6 GB".
    let sizeDescription: String

    /// Constant: only one of these is ever on screen, and it is about the one model that can
    /// be downloaded.
    var id: String { "gemmaDownload" }

    var title: String { "Read receipts more accurately?" }

    var message: String {
        """
        Gemma reads awkward receipts far more accurately than the built-in parser, and runs \
        entirely on your iPhone — nothing is sent anywhere.

        It's a \(sizeDescription) download. This receipt will be read once it finishes.
        """
    }

    var acceptTitle: String { "Download" }
    var declineTitle: String { "Not now" }
}

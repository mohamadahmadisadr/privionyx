import Foundation

nonisolated enum OCRServiceError: LocalizedError, Sendable {
    case unsupportedImage

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            "The selected image could not be processed."
        }
    }
}

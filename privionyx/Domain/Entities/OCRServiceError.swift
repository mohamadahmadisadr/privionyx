import Foundation

enum OCRServiceError: LocalizedError {
    case unsupportedImage

    var errorDescription: String? {
        switch self {
        case .unsupportedImage:
            "The selected image could not be processed."
        }
    }
}

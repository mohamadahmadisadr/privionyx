import Foundation

nonisolated enum ReceiptProcessingStatus: String, Sendable {
    case scanned = "Scanned"
    case reviewed = "Reviewed"
    case flagged = "Needs Review"
}

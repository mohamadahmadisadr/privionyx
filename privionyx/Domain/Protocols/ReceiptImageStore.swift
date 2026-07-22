import Foundation

protocol ReceiptImageStore: Sendable {
    func saveImageData(_ data: Data, for id: UUID, replacing existingPath: String?) throws -> String
    func loadImageData(at path: String?) -> Data?
    func deleteImage(at path: String?) throws
}

import Foundation

struct ReceiptFileStorage {
    private let fileManager = FileManager.default

    func saveImageData(_ data: Data, for id: UUID, replacing existingPath: String?) throws -> String {
        let destinationURL = imageURL(for: id)

        if let existingPath, existingPath.isEmpty == false, existingPath != destinationURL.path {
            try deleteImage(at: existingPath)
        }

        try ensureDirectoryExists()
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL.path
    }

    func loadImageData(at path: String?) -> Data? {
        guard let path, path.isEmpty == false else { return nil }
        return fileManager.contents(atPath: path)
    }

    func deleteImage(at path: String?) throws {
        guard let path, path.isEmpty == false else { return }
        guard fileManager.fileExists(atPath: path) else { return }
        try fileManager.removeItem(atPath: path)
    }

    private func imageURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString).jpg")
    }

    private var directoryURL: URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return baseURL
            .appendingPathComponent("Privionyx", isDirectory: true)
            .appendingPathComponent("ReceiptImages", isDirectory: true)
    }

    private func ensureDirectoryExists() throws {
        if fileManager.fileExists(atPath: directoryURL.path) == false {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }
}

extension ReceiptFileStorage: ReceiptImageStore {}

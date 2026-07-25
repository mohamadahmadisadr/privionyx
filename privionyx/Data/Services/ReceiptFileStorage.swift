import Foundation

nonisolated struct ReceiptFileStorage: Sendable {
    /// Not stored: `FileManager` is not `Sendable`, and holding one would make this type
    /// unusable from the background context the repository writes on. `FileManager.default`
    /// is documented as safe to use from multiple threads, which is exactly the access this
    /// type makes of it.
    private var fileManager: FileManager { .default }

    /// Persists the image and returns a **relative** identifier (the filename only).
    ///
    /// Storing a filename rather than an absolute path is deliberate: the app's data
    /// container path changes across reinstalls, so an absolute path saved on one launch
    /// no longer resolves on the next. The filename is re-resolved against the current
    /// image directory every time it's read.
    func saveImageData(_ data: Data, for id: UUID, replacing existingPath: String?) throws -> String {
        let newFilename = "\(id.uuidString).jpg"
        let destinationURL = directoryURL.appendingPathComponent(newFilename)

        if let existingPath, existingPath.isEmpty == false, filename(from: existingPath) != newFilename {
            try deleteImage(at: existingPath)
        }

        try ensureDirectoryExists()
        try data.write(to: destinationURL, options: .atomic)
        return newFilename
    }

    func loadImageData(at path: String?) -> Data? {
        guard let url = resolvedURL(for: path) else { return nil }
        return try? Data(contentsOf: url)
    }

    func deleteImage(at path: String?) throws {
        guard let url = resolvedURL(for: path) else { return }
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    /// Resolves a stored value — a bare filename, or a legacy absolute path — to a URL in
    /// the current image directory. Using the last path component makes both forms work.
    private func resolvedURL(for path: String?) -> URL? {
        guard let path, path.isEmpty == false else { return nil }
        return directoryURL.appendingPathComponent(filename(from: path))
    }

    private func filename(from path: String) -> String {
        (path as NSString).lastPathComponent
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

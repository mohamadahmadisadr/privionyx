import Foundation
import Testing
@testable import privionyx

/// Guards the fix for images disappearing after a reinstall: the store must persist a bare
/// file name, not an absolute path that embeds the (per-install) data container UUID.
@Suite("Receipt file storage")
struct ReceiptFileStorageTests {
    @Test("Saving returns a bare file name, not an absolute path")
    func saveReturnsFileName() throws {
        let storage = ReceiptFileStorage()
        let id = UUID()
        let data = Data(repeating: 0x7F, count: 1_024)

        let stored = try storage.saveImageData(data, for: id, replacing: nil)
        defer { try? storage.deleteImage(at: stored) }

        #expect(stored.contains("/") == false, "stored value must be a file name, not a path: \(stored)")
        #expect(stored == "\(id.uuidString).jpg")
        #expect(storage.loadImageData(at: stored) == data)
    }

    /// A row written before the fix holds an absolute path under an old container UUID. As
    /// long as the file itself is present in the current container, re-rooting its last
    /// component must still find it.
    @Test("A legacy absolute path resolves to the current container")
    func legacyAbsolutePathResolves() throws {
        let storage = ReceiptFileStorage()
        let id = UUID()
        let data = Data(repeating: 0x2A, count: 512)

        let fileName = try storage.saveImageData(data, for: id, replacing: nil)
        defer { try? storage.deleteImage(at: fileName) }

        let staleAbsolutePath = "/var/mobile/Containers/Data/Application/OLD-CONTAINER-UUID/Library/Application Support/Privionyx/ReceiptImages/\(fileName)"

        #expect(storage.loadImageData(at: staleAbsolutePath) == data)
    }
}

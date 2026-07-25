import CryptoKit
import Foundation
import Testing
@testable import privionyx

/// A finished download used to be accepted on size alone, and generously: anything over half
/// the expected length reported `.ready`. The failure that produced was the worst shape
/// available — the app said the model was installed, and the truth only surfaced later at
/// load, as an engine error with nothing on screen connecting it to a bad transfer.
///
/// These exercise the real install path against small files, since what is being checked is
/// the verification and not the size of the thing verified.
@Suite("Gemma download verification")
struct GemmaDownloadVerificationTests {
    private static let content = "privionyx"
    private static let contentDigest = "41fd4eb55d0e258d9395bc5613856b70034be4ca830b1aa47971179ac4aaa2f2"

    /// A spec standing in for the real one, named so nothing it writes can collide with an
    /// actual downloaded model.
    private func testSpec(
        expectedBytes: Int64 = Int64(content.utf8.count),
        sha256: String = contentDigest
    ) -> GemmaModelSpec {
        GemmaModelSpec(
            id: "test-model",
            displayName: "Test Model",
            repo: "example/test-model",
            filename: "privionyx-download-verification-test.bin",
            remoteURL: URL(string: "https://example.com/test.bin")!,
            expectedBytes: expectedBytes,
            sha256: sha256,
            minPhysicalRAMBytes: 0
        )
    }

    /// `installDownload` moves its source, so every case needs its own.
    private func makeDownloadedFile(_ body: String = content) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func installedFileExists(for spec: GemmaModelSpec) -> Bool {
        FileManager.default.fileExists(atPath: GemmaModelManager.destinationURL(for: spec).path)
    }

    private func removeInstalled(_ spec: GemmaModelSpec) {
        try? FileManager.default.removeItem(at: GemmaModelManager.destinationURL(for: spec))
    }

    @Test("A file whose bytes match the spec is installed")
    func matchingDownloadInstalls() throws {
        let spec = testSpec()
        defer { removeInstalled(spec) }
        let downloaded = try makeDownloadedFile()

        let installed = try GemmaModelManager.installDownload(from: downloaded, spec: spec)

        #expect(installed == GemmaModelManager.destinationURL(for: spec))
        #expect(try String(contentsOf: installed, encoding: .utf8) == Self.content)
    }

    @Test("A truncated file is rejected")
    func truncatedDownloadRejected() throws {
        // The old check passed anything over half the expected size, which this clears.
        let spec = testSpec(expectedBytes: 16)
        defer { removeInstalled(spec) }
        let downloaded = try makeDownloadedFile()

        #expect(throws: GemmaDownloadError.self) {
            try GemmaModelManager.installDownload(from: downloaded, spec: spec)
        }
        #expect(installedFileExists(for: spec) == false)
    }

    /// The case size can never catch: a transfer that resumed from the wrong offset, or a
    /// mirror serving a different build. Right length, wrong bytes.
    @Test("A file of the right length but the wrong contents is rejected")
    func wrongContentsRejected() throws {
        let spec = testSpec()
        defer { removeInstalled(spec) }
        let impostor = try makeDownloadedFile("PRIVIONYX")

        #expect(throws: GemmaDownloadError.self) {
            try GemmaModelManager.installDownload(from: impostor, spec: spec)
        }
        #expect(installedFileExists(for: spec) == false)
    }

    @Test("The digest is computed over the whole file")
    func digestMatchesAKnownValue() throws {
        let url = try makeDownloadedFile()
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try GemmaModelManager.sha256(ofFileAt: url) == Self.contentDigest)
    }

    /// Chunked reading has to give the same answer as one read of the whole file, and the
    /// megabyte boundary is where it would stop doing so.
    @Test("A file larger than one read chunk hashes correctly")
    func digestSpansChunks() throws {
        let body = String(repeating: "gemma", count: 300_000) // ~1.5 MB, over the 1 MB chunk
        let url = try makeDownloadedFile(body)
        defer { try? FileManager.default.removeItem(at: url) }

        let inOneGo = SHA256.hash(data: Data(body.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(try GemmaModelManager.sha256(ofFileAt: url) == inOneGo)
    }
}

import Foundation

/// One ground-truth receipt in the accuracy corpus.
///
/// A fixture is a single self-contained `*.fixture.json` file. It carries either
/// `rawText` (a text fixture, which exercises parsing only) or `image` (an image
/// fixture, which exercises the whole capture-to-draft pipeline) — never both.
struct ReceiptFixture: Sendable {
    enum Source: Sendable {
        /// Raw OCR text, transcribed by hand. Isolates the parsing stage from OCR noise.
        case rawText(String)
        /// A receipt photo in the test bundle. Measures the pipeline end to end.
        case image(URL)
    }

    let name: String
    let notes: String?
    let source: Source
    let expected: ExpectedFields
}

/// The hand-written truth for a fixture. `nil` means "this receipt genuinely has no
/// such field" — which is different from "the parser failed to find it", and the
/// comparison in `FieldOutcome` keeps the two apart.
struct ExpectedFields: Decodable, Sendable {
    let merchant: String?
    /// ISO `yyyy-MM-dd`, interpreted in the current time zone to match `DateExtractor`.
    let date: String?
    let total: Double?
    let subtotal: Double?
    let tax: Double?
    let tip: Double?
    let category: String?

    var expectedDate: Date? {
        date.flatMap(ExpectedFields.isoFormatter.date(from:))
    }

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private final class CorpusBundleAnchor {}

enum ReceiptCorpus {
    enum LoadError: Error, CustomStringConvertible {
        case malformed(name: String, underlying: Error)
        case ambiguousSource(name: String)
        case missingImage(name: String, image: String)

        var description: String {
            switch self {
            case let .malformed(name, underlying):
                "fixture '\(name)' could not be decoded: \(underlying)"
            case let .ambiguousSource(name):
                "fixture '\(name)' must declare exactly one of 'rawText' or 'image'"
            case let .missingImage(name, image):
                "fixture '\(name)' references image '\(image)', which is not in the test bundle"
            }
        }
    }

    static var bundle: Bundle { Bundle(for: CorpusBundleAnchor.self) }

    /// Every fixture in the bundle, sorted by name so report output is stable across runs.
    static func load() throws -> [ReceiptFixture] {
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let fixtureURLs = urls
            .filter { $0.lastPathComponent.hasSuffix(".fixture.json") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try fixtureURLs.map(decode(at:))
    }

    static func textFixtures() throws -> [ReceiptFixture] {
        try load().filter { if case .rawText = $0.source { true } else { false } }
    }

    static func imageFixtures() throws -> [ReceiptFixture] {
        try load().filter { if case .image = $0.source { true } else { false } }
    }

    private static func decode(at url: URL) throws -> ReceiptFixture {
        let name = url.lastPathComponent.replacingOccurrences(of: ".fixture.json", with: "")

        let file: FixtureFile
        do {
            file = try JSONDecoder().decode(FixtureFile.self, from: Data(contentsOf: url))
        } catch {
            throw LoadError.malformed(name: name, underlying: error)
        }

        let source: ReceiptFixture.Source
        switch (file.rawText, file.image) {
        case let (rawText?, nil):
            source = .rawText(rawText.joined(separator: "\n"))
        case let (nil, image?):
            guard let imageURL = imageURL(named: image) else {
                throw LoadError.missingImage(name: name, image: image)
            }
            source = .image(imageURL)
        default:
            throw LoadError.ambiguousSource(name: name)
        }

        return ReceiptFixture(name: name, notes: file.notes, source: source, expected: file.expected)
    }

    /// Synced-group resources land flat in the bundle root, so resolve by base name
    /// and extension rather than by the path written in the fixture.
    private static func imageURL(named image: String) -> URL? {
        let name = (image as NSString).deletingPathExtension
        let ext = (image as NSString).pathExtension
        return bundle.url(forResource: name, withExtension: ext.isEmpty ? nil : ext)
    }

    /// `rawText` is authored as an array of lines so fixtures stay readable as receipts
    /// in the JSON; the loader joins them the way OCR would emit them.
    private struct FixtureFile: Decodable {
        let notes: String?
        let rawText: [String]?
        let image: String?
        let expected: ExpectedFields
    }
}

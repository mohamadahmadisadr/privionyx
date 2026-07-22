import Foundation
import Testing
import UIKit
@testable import privionyx

/// Not an accuracy test — a window into what the OCR stage actually hands the parser.
///
/// When an image fixture fails it is rarely obvious whether recognition produced garbage
/// or extraction mishandled good input. This dumps the intermediate result so the two can
/// be told apart. Run it explicitly:
/// `xcodebuild test -only-testing:privionyxTests/OCRDiagnosticTests`
@Suite("OCR diagnostics")
struct OCRDiagnosticTests {
    @Test("Dump recognized lines for every image fixture")
    func dumpRecognizedLines() async throws {
        let fixtures = try ReceiptCorpus.imageFixtures()
        try #require(fixtures.isEmpty == false, "no image fixtures to diagnose")

        for fixture in fixtures {
            guard case let .image(url) = fixture.source else { continue }
            let image = try #require(UIImage(contentsOfFile: url.path))

            let start = ContinuousClock.now
            let result = try await VisionOCRService().recognizeText(in: image)
            let elapsed = ContinuousClock.now - start

            var out = "\n=== OCR DUMP: \(fixture.name) ===\n"
            out += "source: \(Int(image.size.width))x\(Int(image.size.height)) @\(image.scale)x"
            out += " · \(elapsed.components.seconds)s · \(result.lines.count) lines"
            out += " · \(result.rawText.count) chars\n\n"

            for (index, line) in result.lines.enumerated() {
                let box = String(
                    format: "x[%.2f-%.2f] y%.3f h%.4f",
                    line.minX, line.maxX, line.midY, line.height
                )
                out += String(format: "%3d  %@  %@\n", index, box, line.text)
            }

            print(out)
        }
    }
}

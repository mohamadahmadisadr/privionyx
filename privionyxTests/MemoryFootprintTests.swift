import Darwin
import Foundation
import Testing
import UIKit
@testable import privionyx

/// Measures how much memory a full-resolution capture costs to process.
///
/// A modern iPhone photo is around 24 megapixels, which is 96 MB as a bitmap before any
/// filtering. The pipeline used to build six preprocessing variants and hold them in an
/// array at once, two of them upscaled by 1.35 — roughly 700 MB of live bitmaps, enough to
/// be killed outright on a device. That fan-out is gone, and this is the check that it
/// stays gone: the ceiling here is a budget, not a description of current behaviour.
@Suite("Memory footprint")
struct MemoryFootprintTests {
    /// Well under the jetsam allowance of even a small device, with room for the rest of
    /// the app. Chosen as a limit worth holding rather than as a fit to what it measures.
    static let budgetBytes: UInt64 = 500 * 1024 * 1024

    @Test("Processing a full-resolution capture stays within budget")
    func fullResolutionCaptureStaysWithinBudget() async throws {
        let fixtures = try ReceiptCorpus.imageFixtures()
        let largest = try #require(
            fixtures.compactMap { fixture -> (String, UIImage)? in
                guard case let .image(url) = fixture.source,
                      let image = UIImage(contentsOfFile: url.path) else { return nil }
                return (fixture.name, image)
            }
            .max { $0.1.size.width * $0.1.size.height < $1.1.size.width * $1.1.size.height },
            "no image fixtures available"
        )

        let (name, image) = largest
        let megapixels = image.size.width * image.size.height / 1_000_000

        let baseline = Self.footprintBytes()
        let peak = Peak(value: baseline)

        // Sampled rather than measured before and after, because the bitmaps that matter are
        // transient — they are released by the time recognition returns.
        let sampler = Task.detached {
            while Task.isCancelled == false {
                peak.observe(Self.footprintBytes())
                try? await Task.sleep(for: .milliseconds(15))
            }
        }

        _ = try await VisionOCRService().recognizeText(in: image)

        sampler.cancel()
        let observed = peak.value
        let delta = observed > baseline ? observed - baseline : 0

        print("""

        === MEMORY FOOTPRINT ===
        fixture   : \(name)
        image     : \(Int(image.size.width))x\(Int(image.size.height)) (\(String(format: "%.1f", megapixels)) MP)
        baseline  : \(Self.megabytes(baseline)) MB
        peak      : \(Self.megabytes(observed)) MB
        delta     : \(Self.megabytes(delta)) MB
        budget    : \(Self.megabytes(Self.budgetBytes)) MB

        """)

        #expect(delta < Self.budgetBytes, "peak grew \(Self.megabytes(delta)) MB over baseline")
    }

    /// Shared between the sampler and the test body.
    private nonisolated final class Peak: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: UInt64

        init(value: UInt64) { storage = value }

        var value: UInt64 {
            lock.lock(); defer { lock.unlock() }
            return storage
        }

        func observe(_ sample: UInt64) {
            lock.lock(); defer { lock.unlock() }
            storage = max(storage, sample)
        }
    }

    /// `phys_footprint` is the figure jetsam actually judges a process on — resident size
    /// understates it, and it is what a memory-limit crash report quotes.
    // `nonisolated` so the detached sampler can call it. The project defaults unannotated
    // declarations to the main actor, and a sampler that had to hop there to read the
    // footprint would be sampling the wrong thing at the wrong moment.
    private nonisolated static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    private static func megabytes(_ bytes: UInt64) -> String {
        String(format: "%.0f", Double(bytes) / 1024 / 1024)
    }
}

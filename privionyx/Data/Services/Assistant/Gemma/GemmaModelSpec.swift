import Foundation

/// Describes one downloadable on-device Gemma model: where it lives on Hugging Face, how
/// big it is, and the memory floor a device needs to run it. Kept a plain value so the
/// catalog can grow to several models (e.g. an E4B tier for iPads) without touching callers.
struct GemmaModelSpec: Identifiable, Equatable, Sendable {
    /// Stable identifier, also used as the on-disk filename stem.
    let id: String
    /// Shown in Settings, e.g. "Gemma 4 E2B".
    let displayName: String
    /// Hugging Face repo, e.g. "litert-community/gemma-4-E2B-it-litert-lm".
    let repo: String
    /// The `.litertlm` file to download from that repo.
    let filename: String
    /// Direct, ungated download URL for `filename`.
    let remoteURL: URL
    /// Expected size on disk. Used for the progress denominator (when the server omits a
    /// content length) and to reject a truncated or error-page download.
    let approxBytes: Int64
    /// Physical-RAM floor below which the model won't load reliably on-device.
    let minPhysicalRAMBytes: UInt64

    /// The Gemma 4 E2B build Google promotes as the phone reference model. ~2.6 GB,
    /// Apache-2.0, ungated — downloadable with a plain HTTPS GET, no token.
    static let gemma4E2B = GemmaModelSpec(
        id: "gemma-4-E2B-it",
        displayName: "Gemma 4 E2B",
        repo: "litert-community/gemma-4-E2B-it-litert-lm",
        filename: "gemma-4-E2B-it.litertlm",
        remoteURL: URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true")!,
        approxBytes: 2_600_000_000,
        // Loading a ~2.6 GB model needs headroom; require ~6 GB of physical RAM.
        minPhysicalRAMBytes: 6 * 1_073_741_824
    )
}

/// Chooses the right model for the hardware the app is running on, or reports that no
/// supported model fits.
enum GemmaModelCatalog {
    /// Every model the app knows how to download, most capable first.
    static let all: [GemmaModelSpec] = [.gemma4E2B]

    /// The best-fitting model for this device, or `nil` when even the smallest exceeds the
    /// device's memory. Selection is by physical RAM so the choice is deterministic and
    /// testable; actual load is still guarded at runtime by the engine.
    static func modelForCurrentDevice(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> GemmaModelSpec? {
        all.first { physicalMemory >= $0.minPhysicalRAMBytes }
    }

    /// A human-readable size like "2.6 GB" for the given spec, for the download button.
    static func sizeDescription(for spec: GemmaModelSpec) -> String {
        ByteCountFormatter.string(fromByteCount: spec.approxBytes, countStyle: .file)
    }
}

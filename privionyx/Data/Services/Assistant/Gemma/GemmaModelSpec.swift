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
    ///
    /// Compared against `ProcessInfo.physicalMemory`, which reports what the kernel leaves
    /// for userspace — always less than the figure a device is marketed with. A floor
    /// written in binary gigabytes is therefore unreachable by the tier it names: 6 GiB is
    /// 6.44 GB in decimal, more RAM than a "6 GB" phone physically has, so the check
    /// silently meant "8 GB or more" and turned every iPhone 15 away.
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
        // Loading a ~2.6 GB model needs headroom, so this is the 6 GB tier and up. Set
        // between what the two tiers actually report rather than at either nominal figure:
        // a 4 GB device reports around 3.7-4.0 GB and a 6 GB device around 5.5-5.9 GB, so
        // 5 GB clears both by roughly a gigabyte and does not depend on how much any given
        // model reserves.
        minPhysicalRAMBytes: 5_000_000_000
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

    /// The smallest floor any known model asks for — what a device has to clear to run
    /// anything at all.
    static var lowestMemoryFloor: UInt64? {
        all.map(\.minPhysicalRAMBytes).min()
    }

    /// A human-readable size like "2.6 GB" for the given spec, for the download button.
    static func sizeDescription(for spec: GemmaModelSpec) -> String {
        ByteCountFormatter.string(fromByteCount: spec.approxBytes, countStyle: .file)
    }

    /// What the device says it has, exact bytes included.
    ///
    /// Shown beside an "unsupported" verdict. The previous floor was wrong by a unit and
    /// nothing on screen said so — the app asserted the device was too small while the
    /// device disagreed, and there was no way to see which figure was being compared.
    /// A rounded size alone would hide exactly that kind of mistake.
    static func memoryDescription(_ bytes: UInt64 = ProcessInfo.processInfo.physicalMemory) -> String {
        let rounded = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
        return "\(rounded) (\(bytes.formatted(.number)) bytes)"
    }
}

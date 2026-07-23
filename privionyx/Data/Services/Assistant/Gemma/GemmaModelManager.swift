import Foundation
import Observation

/// Single source of truth for the on-device Gemma model: whether the device can run it,
/// whether the weights are downloaded, download progress, and the on-disk location the
/// engine loads from.
///
/// Shared instance because `AssistantBackend.makeAssistant()` takes no arguments and the
/// Settings UI must observe the same download state the engine reads from.
@MainActor
@Observable
final class GemmaModelManager {
    static let shared = GemmaModelManager()

    enum State: Equatable {
        /// The device doesn't meet the memory floor for any known model.
        case unsupported
        /// A model fits this device but hasn't been downloaded.
        case notDownloaded
        /// Download in flight, `progress` in 0...1.
        case downloading(progress: Double)
        /// Weights are present on disk and ready to load.
        case ready(URL)
        /// The last attempt failed; the message is shown to the user.
        case failed(String)
    }

    private(set) var state: State

    /// The model chosen for this device, or `nil` when unsupported.
    let spec: GemmaModelSpec?

    private let fileManager = FileManager.default
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var resumeData: Data?

    init(spec: GemmaModelSpec? = GemmaModelCatalog.modelForCurrentDevice()) {
        self.spec = spec
        state = spec == nil ? .unsupported : .notDownloaded
        refreshState()
    }

    // MARK: - Derived

    var readyModelURL: URL? {
        if case let .ready(url) = state { return url }
        return nil
    }

    var isReady: Bool { readyModelURL != nil }

    /// Reconciles state with what's actually on disk. Safe to call on every appearance;
    /// leaves an in-flight download untouched.
    func refreshState() {
        guard let spec else { state = .unsupported; return }
        if case .downloading = state { return }

        let url = Self.destinationURL(for: spec)
        if isCompleteFile(at: url, spec: spec) {
            state = .ready(url)
        } else if case .failed = state {
            // Preserve the failure message until the user retries.
        } else {
            state = .notDownloaded
        }
    }

    // MARK: - Commands

    func download() {
        guard let spec else { state = .unsupported; return }
        switch state {
        case .downloading, .ready:
            return
        default:
            break
        }

        if let free = freeDiskSpace(), free < spec.approxBytes + 500_000_000 {
            state = .failed("Not enough free space. Free up about \(GemmaModelCatalog.sizeDescription(for: spec)) and try again.")
            return
        }

        state = .downloading(progress: 0)

        let session = makeSession(for: spec)
        let task = resumeData.map { session.downloadTask(withResumeData: $0) }
            ?? session.downloadTask(with: spec.remoteURL)
        resumeData = nil
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel(byProducingResumeData: { [weak self] data in
            Task { @MainActor in self?.resumeData = data }
        })
        task = nil
        if case .downloading = state { state = .notDownloaded }
    }

    func deleteModel() {
        cancel()
        resumeData = nil
        if let spec {
            try? fileManager.removeItem(at: Self.destinationURL(for: spec))
        }
        state = spec == nil ? .unsupported : .notDownloaded
    }

    // MARK: - Delegate callbacks (invoked on the main actor)

    fileprivate func handleProgress(_ progress: Double) {
        guard case .downloading = state else { return }
        state = .downloading(progress: min(max(progress, 0), 1))
    }

    fileprivate func handleFinished(url: URL) {
        task = nil
        resumeData = nil
        state = .ready(url)
    }

    fileprivate func handleFailure(_ message: String, resumeData: Data?) {
        task = nil
        self.resumeData = resumeData
        state = .failed(message)
    }

    // MARK: - Storage

    /// `Application Support/Privionyx/Models/<filename>` — same convention as
    /// `ReceiptFileStorage`, kept out of Documents so it isn't user-visible.
    nonisolated static func modelsDirectory() -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("Privionyx", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    nonisolated static func destinationURL(for spec: GemmaModelSpec) -> URL {
        modelsDirectory().appendingPathComponent(spec.filename)
    }

    /// Moves a freshly downloaded temp file into place, rejecting a truncated or error-page
    /// download by size, and excludes the large blob from iCloud backup. Runs synchronously
    /// inside the download delegate because the source temp file is deleted once the
    /// callback returns.
    nonisolated static func installDownload(from location: URL, spec: GemmaModelSpec) throws -> URL {
        let fileManager = FileManager.default
        let directory = modelsDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let downloadedSize = (try? fileManager.attributesOfItem(atPath: location.path))?[.size] as? Int64 ?? 0
        guard downloadedSize > spec.approxBytes / 2 else {
            throw GemmaDownloadError.corrupted
        }

        var destination = destinationURL(for: spec)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: location, to: destination)

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? destination.setResourceValues(resourceValues)

        return destination
    }

    private func isCompleteFile(at url: URL, spec: GemmaModelSpec) -> Bool {
        guard let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size]) as? Int64 else {
            return false
        }
        return size > spec.approxBytes / 2
    }

    private func freeDiskSpace() -> Int64? {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private func makeSession(for spec: GemmaModelSpec) -> URLSession {
        if let session { return session }
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        let delegate = DownloadDelegate(manager: self, spec: spec)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.session = session
        return session
    }
}

enum GemmaDownloadError: LocalizedError {
    case corrupted

    var errorDescription: String? {
        switch self {
        case .corrupted:
            "The download didn't complete correctly. Please try again."
        }
    }
}

/// Bridges URLSession's background-queue callbacks onto the main-actor manager. The
/// finished-download move happens synchronously here because the temp file is gone once
/// this returns.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var manager: GemmaModelManager?
    let spec: GemmaModelSpec

    init(manager: GemmaModelManager, spec: GemmaModelSpec) {
        self.manager = manager
        self.spec = spec
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : spec.approxBytes
        let progress = expected > 0 ? Double(totalBytesWritten) / Double(expected) : 0
        Task { @MainActor [manager] in manager?.handleProgress(progress) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let installed = try GemmaModelManager.installDownload(from: location, spec: spec)
            Task { @MainActor [manager] in manager?.handleFinished(url: installed) }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "The download couldn't be saved."
            Task { @MainActor [manager] in manager?.handleFailure(message, resumeData: nil) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return } // success is handled in didFinishDownloadingTo
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return } // user cancelled; state already handled

        let resume = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task { @MainActor [manager] in
            manager?.handleFailure(error.localizedDescription, resumeData: resume)
        }
    }
}

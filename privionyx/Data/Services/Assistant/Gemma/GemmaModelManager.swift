import CryptoKit
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
    /// Handed over when the system relaunches the app purely to deliver download events.
    /// Must be called once the session says it has finished delivering them.
    private var backgroundEventsCompletion: (() -> Void)?

    /// Stable across launches: recreating a session with the same identifier is how a
    /// download started by a previous launch is reattached rather than restarted.
    private static let backgroundSessionIdentifier = "dev.sadr.privionyx.gemma-model-download"

    /// Whether the user has opted into spending cellular data on the model.
    ///
    /// Absent means `false`, which is the default worth having: 2.6 GB is more than many
    /// monthly allowances, and a background session will happily spend it without ever
    /// surfacing the cost. Read from defaults at download time rather than cached, so the
    /// toggle in Settings takes effect on the next attempt without any wiring between them.
    static let allowsCellularDownloadKey = "privionyx.gemma.allowsCellularDownload"

    private let defaults: UserDefaults

    var allowsCellularDownload: Bool {
        defaults.bool(forKey: Self.allowsCellularDownloadKey)
    }

    init(
        spec: GemmaModelSpec? = GemmaModelCatalog.modelForCurrentDevice(),
        defaults: UserDefaults = .standard
    ) {
        self.spec = spec
        self.defaults = defaults
        state = spec == nil ? .unsupported : .notDownloaded
        refreshState()
    }

    /// The request the download runs as.
    ///
    /// The constraint goes on the request rather than the session configuration because the
    /// background session is created once and cached for the lifetime of the process — its
    /// configuration is fixed long before the user can change their mind, and a resumed task
    /// carries the original request's constraints with it.
    ///
    /// `allowsConstrainedNetworkAccess` is `false` regardless of the preference: Low Data Mode
    /// is the user asking for restraint in the one place the system provides to ask, and a
    /// multi-gigabyte download is exactly what they meant.
    nonisolated static func makeRequest(for spec: GemmaModelSpec, allowsCellular: Bool) -> URLRequest {
        var request = URLRequest(url: spec.remoteURL)
        request.allowsExpensiveNetworkAccess = allowsCellular
        request.allowsConstrainedNetworkAccess = false
        return request
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

        if let free = freeDiskSpace(), free < spec.expectedBytes + 500_000_000 {
            state = .failed("Not enough free space. Free up about \(GemmaModelCatalog.sizeDescription(for: spec)) and try again.")
            return
        }

        state = .downloading(progress: 0)

        let session = makeSession(for: spec)
        let task = resumeData.map { session.downloadTask(withResumeData: $0) }
            ?? session.downloadTask(with: Self.makeRequest(for: spec, allowsCellular: allowsCellularDownload))
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
        // Bytes arriving *are* the evidence a download is in flight. After a relaunch these
        // can land before `reconnectToBackgroundSession` has restored the state, so this
        // accepts them rather than dropping them on the old `.downloading` guard.
        guard spec != nil, isReady == false else { return }
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

    /// Moves a freshly downloaded temp file into place once its bytes are confirmed to be the
    /// ones the spec names, and excludes the large blob from iCloud backup. Runs synchronously
    /// inside the download delegate because the source temp file is deleted once the callback
    /// returns — which is also the only moment the download can be rejected without having
    /// already told the user it is ready.
    ///
    /// Size is checked first because it is free and catches the ordinary truncation. The
    /// digest is what catches the rest: a resumed transfer that stitched together the wrong
    /// ranges, a captive-portal HTML page padded to length, a mirror serving a different
    /// build. All of those used to reach `.ready` and fail at load, where nothing on screen
    /// could explain why.
    nonisolated static func installDownload(from location: URL, spec: GemmaModelSpec) throws -> URL {
        let fileManager = FileManager.default
        let directory = modelsDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let downloadedSize = (try? fileManager.attributesOfItem(atPath: location.path))?[.size] as? Int64 ?? 0
        guard downloadedSize == spec.expectedBytes else {
            throw GemmaDownloadError.corrupted
        }
        guard try sha256(ofFileAt: location).caseInsensitiveCompare(spec.sha256) == .orderedSame else {
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

    /// Hex SHA-256 of a file, read a megabyte at a time.
    ///
    /// Streamed rather than `Data(contentsOf:)` because the file is 2.6 GB and the whole point
    /// of the runtime mapping it is that it never has to be resident.
    nonisolated static func sha256(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), chunk.isEmpty == false {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Whether the file on disk is the one that was installed.
    ///
    /// Size only. The digest was checked when the file was written and nothing but this app
    /// writes to the directory, so re-hashing 2.6 GB on every appearance of the Settings
    /// screen would buy nothing. Exact equality rather than a fraction: an install that
    /// passed verification has exactly this length, so anything else is a file that was
    /// truncated or replaced afterwards.
    private func isCompleteFile(at url: URL, spec: GemmaModelSpec) -> Bool {
        guard let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size]) as? Int64 else {
            return false
        }
        return size == spec.expectedBytes
    }

    private func freeDiskSpace() -> Int64? {
        let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// The one session for this process.
    ///
    /// Background rather than default: the model is measured in gigabytes, and a default
    /// session is suspended when the user leaves the app and its tasks cancelled shortly
    /// after — so a download only completed if the user sat and watched it. A background
    /// session is run by the system daemon and survives the app being suspended or killed.
    ///
    /// Cached because creating a second session with the same identifier is an error, and
    /// never invalidated because it is meant to outlive any particular screen.
    private func makeSession(for spec: GemmaModelSpec) -> URLSession {
        if let session { return session }

        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        // The user pressed Download and is watching a progress bar, so this shouldn't be
        // deferred to whenever the system considers convenient.
        config.isDiscretionary = false
        // Relaunch the app in the background to deliver completion if it isn't running.
        config.sessionSendsLaunchEvents = true
        // `waitsForConnectivity` is deliberately not set: background sessions ignore it and
        // wait for connectivity regardless.

        let delegate = DownloadDelegate(manager: self, spec: spec)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.session = session
        return session
    }

    // MARK: - Reattaching across launches

    /// Routes the system's background-session callback to the manager. Called from the app
    /// delegate when the app is relaunched to deliver download events.
    static func handleBackgroundSessionEvents(identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == backgroundSessionIdentifier else {
            // Not ours — the system still expects the handler to be called.
            completionHandler()
            return
        }

        shared.backgroundEventsCompletion = completionHandler
        shared.reconnectToBackgroundSession()
    }

    /// Rebuilds the session so the system can hand back a download left running by an
    /// earlier launch, and restores the progress state for one still in flight. Safe to call
    /// on every launch; does nothing when there is no download to adopt.
    func reconnectToBackgroundSession() {
        guard let spec else { return }

        makeSession(for: spec).getAllTasks { [weak self] tasks in
            guard let inFlight = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first else { return }

            Task { @MainActor in
                self?.adopt(inFlight, spec: spec)
            }
        }
    }

    private func adopt(_ downloadTask: URLSessionDownloadTask, spec: GemmaModelSpec) {
        guard isReady == false else { return }

        task = downloadTask
        let expected = downloadTask.countOfBytesExpectedToReceive > 0
            ? downloadTask.countOfBytesExpectedToReceive
            : spec.expectedBytes
        let fraction = expected > 0 ? Double(downloadTask.countOfBytesReceived) / Double(expected) : 0
        state = .downloading(progress: min(max(fraction, 0), 1))
    }

    fileprivate func finishBackgroundEvents() {
        backgroundEventsCompletion?()
        backgroundEventsCompletion = nil
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
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : spec.expectedBytes
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

    /// The system has finished replaying everything that happened while the app was away.
    /// Calling the stored handler is what lets it suspend us again.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [manager] in manager?.finishBackgroundEvents() }
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

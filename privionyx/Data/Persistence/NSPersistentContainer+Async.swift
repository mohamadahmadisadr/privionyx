import CoreData

extension NSPersistentContainer {
    /// `performBackgroundTask` with a return value.
    ///
    /// The closure genuinely runs on a private queue that is not the caller's actor, so it is
    /// `@Sendable` and `T` is constrained to `Sendable`. Neither was true before, and under
    /// Swift 5's language mode nothing said so: the closure could capture main-actor state and
    /// touch it from Core Data's queue, and could hand back a type with no thread-safety story
    /// at all. Both were sound only because the callers happened to behave.
    ///
    /// The one thing that must never cross this boundary is an `NSManagedObject`. Objects
    /// belong to the context they were fetched into, and constraining `T` is what makes that
    /// a compile error rather than an occasional crash — the repository maps rows into
    /// `ReceiptItem` values before returning.
    nonisolated func performBackgroundTask<T: Sendable>(
        _ work: @escaping @Sendable (NSManagedObjectContext) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            performBackgroundTask { context in
                do {
                    let result = try work(context)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

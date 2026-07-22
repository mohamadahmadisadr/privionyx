import CoreData

extension NSPersistentContainer {
    func performBackgroundTask<T>(_ work: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
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

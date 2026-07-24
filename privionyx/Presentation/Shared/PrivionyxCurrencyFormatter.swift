import Foundation

enum PrivionyxCurrencyFormatter {
    static var currentCurrencyCode: String {
        Locale.autoupdatingCurrent.currency?.identifier ?? Locale.current.currency?.identifier ?? "USD"
    }

    static func string(for amount: Double) -> String {
        Cache.shared.string(for: amount)
    }

    /// Holds the live formatter so it isn't rebuilt per call.
    ///
    /// `NumberFormatter` is expensive to construct, and this is the app's hottest formatting
    /// path: every receipt row, every dashboard figure, every insight — and once per receipt
    /// inside the receipt list's search filter, which re-runs on each keystroke. A search over
    /// a few hundred receipts was allocating a formatter per receipt per character typed.
    ///
    /// Formatting happens under the lock rather than handing the instance out, so correctness
    /// doesn't rest on `NumberFormatter`'s threading guarantees. The lock is uncontended in
    /// practice — callers are effectively all on the main actor.
    private final class Cache: @unchecked Sendable {
        static let shared = Cache()

        private let lock = NSLock()
        private var formatter: NumberFormatter?
        private var currencyCode = PrivionyxCurrencyFormatter.currentCurrencyCode

        private init() {
            // The one thing that can invalidate a configured formatter. Rebuilt lazily on the
            // next call rather than eagerly in the notification.
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(invalidate),
                name: NSLocale.currentLocaleDidChangeNotification,
                object: nil
            )
        }

        func string(for amount: Double) -> String {
            lock.lock()
            defer { lock.unlock() }

            let formatter = self.formatter ?? makeFormatter()

            return formatter.string(from: NSNumber(value: amount))
                ?? amount.formatted(.currency(code: currencyCode).presentation(.isoCode))
        }

        /// Caller must hold `lock`.
        private func makeFormatter() -> NumberFormatter {
            currencyCode = PrivionyxCurrencyFormatter.currentCurrencyCode

            let formatter = NumberFormatter()
            formatter.locale = Locale.autoupdatingCurrent
            formatter.numberStyle = .currencyISOCode
            formatter.currencyCode = currencyCode
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2

            self.formatter = formatter
            return formatter
        }

        @objc private func invalidate() {
            lock.lock()
            formatter = nil
            lock.unlock()
        }
    }
}

import Foundation

enum PrivionyxCurrencyFormatter {
    static var currentCurrencyCode: String {
        Locale.autoupdatingCurrent.currency?.identifier ?? Locale.current.currency?.identifier ?? "USD"
    }

    static func string(for amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.numberStyle = .currencyISOCode
        formatter.currencyCode = currentCurrencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2

        return formatter.string(from: NSNumber(value: amount))
            ?? amount.formatted(.currency(code: currentCurrencyCode).presentation(.isoCode))
    }
}

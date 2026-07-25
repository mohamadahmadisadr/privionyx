import Foundation
import UIKit

/// A small library of example receipts, loaded only when someone asks for it.
///
/// It ships in release builds now rather than being debug-only. An empty app is impossible to
/// evaluate — an App Store reviewer has no receipts, no printed paper, and no camera in the
/// simulator, so without this there is no path from launching the app to seeing it work. The
/// same is true of anyone deciding whether to keep it.
///
/// **Nothing is loaded unless the user taps a button.** Sample receipts are otherwise ordinary
/// receipts and count towards the dashboard, budgets and recurring charges exactly as real ones
/// do, which is the point — and also the hazard, since someone who tries them and then starts
/// scanning would have their real figures mixed with fiction. Hence `tag`: every sample carries
/// it, so removal takes back precisely what was added and nothing the user typed, and the tag
/// is visible on the row and in the detail view so no sample is mistaken for a real receipt.
nonisolated enum PrivionyxSampleData {
    /// Written into `tags` on every sample, and the only way the app can tell one apart from a
    /// receipt the user entered. Capitalised as it is displayed.
    static let tag = "Sample"

    /// Development shortcut, unrelated to the user-facing button: seeds on launch so the
    /// dashboard and assistant can be exercised without tapping through. Debug builds only.
    static let launchArgument = "-privionyxSampleData"

    static var isRequested: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(launchArgument)
        #else
        false
        #endif
    }

    static func drafts(relativeTo now: Date = .now) -> [ReceiptDraft] {
        let calendar = Calendar.current

        func date(daysAgo: Int) -> Date {
            calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        }

        let entries: [(String, Double, Double?, Int, ReceiptCategory)] = [
            ("Blue Bottle Coffee", 18.90, 1.24, 0, .dining),
            ("Uber", 24.50, nil, 0, .travel),
            ("Whole Foods Market", 86.32, 4.31, 1, .grocery),
            ("Amazon", 142.99, 8.15, 2, .shopping),
            ("Delta Air Lines", 412.00, nil, 3, .travel),
            ("Shell", 61.40, 3.07, 5, .gas),
            ("Trader Joe's", 34.87, 2.14, 6, .grocery),
            ("Hydro One", 98.20, nil, 9, .utilities),
            ("Sweetgreen", 21.75, 1.42, 11, .dining),
            ("Best Buy", 219.99, 12.30, 14, .shopping)
        ]

        return entries.map { merchant, amount, tax, daysAgo, category in
            ReceiptDraft(
                merchant: merchant,
                amount: amount,
                subtotal: tax.map { amount - $0 },
                tax: tax,
                tip: nil,
                date: date(daysAgo: daysAgo),
                category: category,
                customCategoryName: nil,
                tags: [Self.tag],
                imageData: receiptImage(merchant: merchant, amount: amount, tax: tax),
                rawText: nil,
                lineItems: [],
                notes: "",
                status: .reviewed
            )
        }
    }

    /// Renders a receipt-like image so the detail screen has something to show for a sample,
    /// mirroring what a real scan would store. Drawn rather than bundled, so ten sample
    /// receipts cost the app download nothing.
    private static func receiptImage(merchant: String, amount: Double, tax: Double?) -> Data? {
        let size = CGSize(width: 600, height: 820)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let mono = UIFont.monospacedSystemFont(ofSize: 30, weight: .regular)
            let bold = UIFont.monospacedSystemFont(ofSize: 34, weight: .bold)

            func draw(_ text: String, at y: CGFloat, font: UIFont) {
                (text as NSString).draw(
                    at: CGPoint(x: 44, y: y),
                    withAttributes: [.font: font, .foregroundColor: UIColor.black]
                )
            }

            draw(merchant.uppercased(), at: 60, font: bold)
            draw("------------------------", at: 120, font: mono)
            draw("SUBTOTAL", at: 200, font: mono)
            draw(String(format: "%.2f", amount - (tax ?? 0)), at: 200, font: mono)
            if let tax {
                draw("TAX", at: 250, font: mono)
                draw(String(format: "%.2f", tax), at: 250, font: mono)
            }
            draw("------------------------", at: 310, font: mono)
            draw("TOTAL", at: 370, font: bold)
            draw(String(format: "%.2f", amount), at: 370, font: bold)
        }
        return image.jpegData(compressionQuality: 0.8)
    }
}

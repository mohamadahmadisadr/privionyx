import Observation
import PhotosUI
import SwiftUI
import UIKit
import VisionKit

@MainActor
@Observable
final class AddReceiptViewModel {
    @ObservationIgnored private let appState: PrivionyxAppState
    @ObservationIgnored private let imageProcessor: any ReceiptImageProcessing
    @ObservationIgnored private let perspectiveService: any ReceiptPerspectiveCorrecting
    @ObservationIgnored private let processReceiptUseCase: ProcessReceiptImageUseCase
    @ObservationIgnored private let merchantRules: any MerchantRuleProviding
    private let editingReceiptID: UUID?

    var merchant = ""
    // Editing a figure by hand makes it the user's, not an inference, so the "calculated"
    // note is withdrawn as soon as they touch it. `apply(draft:)` assigns `derivedTotals`
    // after these, so loading a draft is unaffected.
    var amount = "" { didSet { derivedTotals.remove(.total) } }
    var subtotal = "" { didSet { derivedTotals.remove(.subtotal) } }
    var tax = "" { didSet { derivedTotals.remove(.tax) } }
    var tip = ""
    var lineItems: [ReceiptLineItem] = []
    var date = Date.now
    var selectedCategory: ReceiptCategory = .shopping
    var customCategoryName = ""
    var tagsText = ""
    var rawText = ""
    /// Totals figures the reconciler computed rather than read. Cleared whenever the user
    /// edits, since a hand-entered figure is no longer an inference.
    var derivedTotals: Set<ReceiptTotalsReconciler.Field> = []
    var totalsStatus: ReceiptTotalsReconciler.Status = .unverified
    /// The merchant name recognition produced for the scan on screen, kept so that saving a
    /// different one can be recognized as a correction rather than as a fresh entry. Empty
    /// for manual entry and for receipts opened from the list, where there is nothing to learn.
    private var recognizedMerchant = ""
    var notes = ""
    var processingState = "Ready"
    var parsingProgress = 0.0
    var previewImage: UIImage?
    var showSavedToast = false
    var didSaveSuccessfully = false
    var ocrSourceImage: UIImage?
    var cropSourceImage: UIImage?
    var cropQuadrilateral = ReceiptQuadrilateral.default
    var isCropEditorPresented = false
    var isDetectingCrop = false
    var isReviewPresented = false
    var isParsingPresented = false

    var isPhotoPickerPresented = false
    var isDocumentScannerPresented = false
    var isRawTextPresented = false
    var selectedPhotoItem: PhotosPickerItem?

    init(
        appState: PrivionyxAppState,
        imageProcessor: any ReceiptImageProcessing,
        perspectiveService: any ReceiptPerspectiveCorrecting,
        processReceiptUseCase: ProcessReceiptImageUseCase,
        merchantRules: any MerchantRuleProviding,
        initialDraft: ReceiptDraft? = nil
    ) {
        self.appState = appState
        self.imageProcessor = imageProcessor
        self.perspectiveService = perspectiveService
        self.processReceiptUseCase = processReceiptUseCase
        self.merchantRules = merchantRules
        self.editingReceiptID = initialDraft?.id

        if let initialDraft {
            merchant = initialDraft.merchant
            amount = initialDraft.amount == .zero ? "" : String(format: "%.2f", initialDraft.amount)
            subtotal = initialDraft.subtotal.map { String(format: "%.2f", $0) } ?? ""
            tax = initialDraft.tax.map { String(format: "%.2f", $0) } ?? ""
            tip = initialDraft.tip.map { String(format: "%.2f", $0) } ?? ""
            lineItems = initialDraft.lineItems
            date = initialDraft.date
            selectedCategory = initialDraft.category
            customCategoryName = initialDraft.customCategoryName ?? ""
            tagsText = initialDraft.tags.joined(separator: ", ")
            rawText = initialDraft.rawText ?? ""
            notes = initialDraft.notes
            previewImage = initialDraft.imageData.flatMap(UIImage.init(data:))
            processingState = "Ready For Review"
        }
    }

    var isEditing: Bool {
        editingReceiptID != nil
    }

    var hasExtractedFields: Bool {
        merchant.isEmpty == false || amount.isEmpty == false
    }

    var hasReviewData: Bool {
        previewImage != nil || hasExtractedFields
    }

    var canRetryOCR: Bool {
        ocrSourceImage != nil
    }

    var canSave: Bool {
        merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        && parsedCurrencyAmount(amount).map { $0 > 0 } == true
    }

    var displayCategoryName: String {
        let customName = customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        return customName.isEmpty ? selectedCategory.rawValue : customName
    }

    var hasRawText: Bool {
        rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var rawTextLineCount: Int {
        rawText
            .components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .count
    }

    var parsedAmount: Double? {
        parsedCurrencyAmount(amount)
    }

    var parsedSubtotal: Double? {
        parsedCurrencyAmount(subtotal)
    }

    var parsedTax: Double? {
        parsedCurrencyAmount(tax)
    }

    var parsedTip: Double? {
        parsedCurrencyAmount(tip)
    }

    var reviewHints: [String] {
        var hints: [String] = []

        if merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hints.append("Merchant needs a quick check.")
        }

        if parsedAmount == nil || parsedAmount == 0 {
            hints.append("Total amount was not detected.")
        }

        if rawTextLineCount > 0, rawTextLineCount < 5 {
            hints.append("Only a few text lines were found. The crop or lighting may need another pass.")
        }

        // A calculated figure is only as good as the two it came from, so name it rather
        // than presenting it with the same confidence as something read off the paper.
        // A total with no subtotal or tax beside it cannot be checked against anything.
        // The figure may well be right, but nothing on the receipt corroborates it, and that
        // is worth saying rather than presenting it with the same weight as one that adds up.
        if totalsStatus == .unverified, parsedAmount != nil, parsedSubtotal == nil, parsedTax == nil {
            hints.append("Only a total was found — there was nothing on the receipt to check it against.")
        }

        if derivedTotals.contains(.total) {
            hints.append("Total was calculated from the subtotal and tax — the total line was not readable.")
        }
        if derivedTotals.contains(.subtotal) {
            hints.append("Subtotal was calculated from the total and tax.")
        }
        if derivedTotals.contains(.tax) {
            hints.append("Tax was calculated from the total and subtotal.")
        }

        if let parsedAmount, let parsedSubtotal {
            let expected = parsedSubtotal + (parsedTax ?? 0) + (parsedTip ?? 0)
            if abs(expected - parsedAmount) > 0.05 {
                hints.append("Subtotal, tax, and tip do not fully match the total.")
            }
        }

        return hints
    }

    var extractionTitle: String {
        if processingState == "Manual Entry" {
            return "Manual entry"
        }
        if reviewHints.isEmpty {
            return "Extraction looks good"
        }
        return "Review recommended"
    }

    var extractionMessage: String {
        if processingState == "Manual Entry" {
            return "Fill in the receipt fields yourself, then save."
        }
        if reviewHints.isEmpty {
            return "Merchant, total, and supporting details are ready for your confirmation."
        }
        return "OCR can be imperfect. Check the highlighted fields before saving."
    }

    var extractionIcon: String {
        reviewHints.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    var extractionTint: Color {
        reviewHints.isEmpty ? PrivionyxTheme.Colors.success : PrivionyxTheme.Colors.warning
    }

    func presentPhotoPicker() {
        isPhotoPickerPresented = true
    }

    func presentCamera() {
        guard VNDocumentCameraViewController.isSupported else {
            appState.lastErrorMessage = "Document scanning is not supported on this device."
            return
        }
        isDocumentScannerPresented = true
    }

    func startManualEntry() {
        recognizedMerchant = ""
        resetDraft()
        processingState = "Manual Entry"
        isReviewPresented = true
    }

    func loadSelectedPhoto() async {
        guard let selectedPhotoItem,
              let data = try? await selectedPhotoItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }

        handleSelectedImage(image)
    }

    func handleSelectedImage(_ image: UIImage?) {
        isDocumentScannerPresented = false
        guard let image else { return }

        beginCropping(for: image)
    }

    func saveReceipt() async {
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amountValue = parsedCurrencyAmount(amount), amountValue > 0, trimmedMerchant.isEmpty == false else {
            appState.lastErrorMessage = "Merchant and amount are required."
            return
        }

        let draft = ReceiptDraft(
            id: editingReceiptID ?? UUID(),
            merchant: trimmedMerchant,
            amount: amountValue,
            subtotal: parsedCurrencyAmount(subtotal),
            tax: parsedCurrencyAmount(tax),
            tip: parsedCurrencyAmount(tip),
            date: date,
            category: selectedCategory,
            customCategoryName: customCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            tags: parsedTags,
            imagePath: nil,
            imageData: previewImage?.jpegData(compressionQuality: 0.82),
            rawText: rawText.isEmpty ? nil : rawText,
            lineItems: lineItems,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .reviewed
        )

        do {
            didSaveSuccessfully = false
            try await appState.saveReceipt(draft)

            // Learn only from a scan the user actually amended. `recognizedMerchant` is empty
            // for manual entry and for receipts opened from the list, so neither teaches
            // anything, and an unchanged name teaches nothing either.
            if recognizedMerchant.isEmpty == false, recognizedMerchant != trimmedMerchant {
                merchantRules.saveMerchantCorrection(
                    recognized: recognizedMerchant,
                    corrected: trimmedMerchant
                )
            }
            didSaveSuccessfully = true
            processingState = "Saved"

            // Editing is its own screen that dismisses on success (the view observes
            // `didSaveSuccessfully`). Leave the fields intact and let it close, rather than
            // blanking the form in place — which looked like the save had failed and made a
            // second tap hit the empty-amount guard.
            guard isEditing == false else { return }

            showSavedToast = true
            resetDraft()

            Task {
                try? await Task.sleep(for: .seconds(1.6))
                showSavedToast = false
            }
        } catch {
            appState.lastErrorMessage = error.localizedDescription
        }
    }

    func confirmCropAndAnalyze() {
        guard let sourceImage = cropSourceImage else { return }

        let croppedImage = perspectiveService.cropReceiptImage(sourceImage, quadrilateral: cropQuadrilateral)
        let enhancedImage = imageProcessor.enhanceReceiptImage(croppedImage)

        ocrSourceImage = croppedImage
        previewImage = enhancedImage
        cropSourceImage = nil
        isCropEditorPresented = false
        analyzeReceipt(from: croppedImage)
    }

    func cancelCropping() {
        cropSourceImage = nil
        isCropEditorPresented = false
        isDetectingCrop = false
        isParsingPresented = false
        selectedPhotoItem = nil
    }

    func dismissReview() {
        isReviewPresented = false
    }

    func retryOCR() {
        guard let sourceImage = ocrSourceImage else { return }
        isReviewPresented = false
        analyzeReceipt(from: sourceImage)
    }

    private func apply(draft: ReceiptDraft) {
        merchant = draft.merchant
        amount = draft.amount == .zero ? "" : String(format: "%.2f", draft.amount)
        subtotal = draft.subtotal.map { String(format: "%.2f", $0) } ?? ""
        tax = draft.tax.map { String(format: "%.2f", $0) } ?? ""
        tip = draft.tip.map { String(format: "%.2f", $0) } ?? ""
        lineItems = draft.lineItems
        date = draft.date
        selectedCategory = draft.category
        customCategoryName = draft.customCategoryName ?? ""
        tagsText = draft.tags.joined(separator: ", ")
        rawText = draft.rawText ?? ""
        notes = draft.notes
        derivedTotals = draft.derivedTotals
        totalsStatus = draft.totalsStatus
    }

    private func beginCropping(for image: UIImage) {
        let normalizedImage = imageProcessor.normalizedImage(image)
        cropSourceImage = normalizedImage
        cropQuadrilateral = .default
        isCropEditorPresented = true
        isDetectingCrop = true
        processingState = "Adjust Crop"

        Task {
            let detectedQuadrilateral = await perspectiveService.detectReceiptQuadrilateral(in: normalizedImage)
            if let detectedQuadrilateral {
                cropQuadrilateral = adjustedCropQuadrilateral(from: detectedQuadrilateral)
            }
            isDetectingCrop = false
        }
    }

    private func adjustedCropQuadrilateral(from quadrilateral: ReceiptQuadrilateral) -> ReceiptQuadrilateral {
        func expanded(_ point: CGPoint, dx: CGFloat, dy: CGFloat) -> CGPoint {
            CGPoint(
                x: min(max(point.x + dx, 0.02), 0.98),
                y: min(max(point.y + dy, 0.02), 0.98)
            )
        }

        return ReceiptQuadrilateral(
            topLeft: expanded(quadrilateral.topLeft, dx: -0.015, dy: 0.015),
            topRight: expanded(quadrilateral.topRight, dx: 0.015, dy: 0.015),
            bottomRight: expanded(quadrilateral.bottomRight, dx: 0.015, dy: -0.015),
            bottomLeft: expanded(quadrilateral.bottomLeft, dx: -0.015, dy: -0.015)
        )
    }

    private func resetDraft() {
        merchant = ""
        amount = ""
        subtotal = ""
        tax = ""
        tip = ""
        lineItems = []
        date = .now
        selectedCategory = .shopping
        customCategoryName = ""
        tagsText = ""
        rawText = ""
        notes = ""
        processingState = "Ready"
        parsingProgress = 0
        previewImage = nil
        ocrSourceImage = nil
        cropSourceImage = nil
        cropQuadrilateral = .default
        isCropEditorPresented = false
        isDetectingCrop = false
        isReviewPresented = false
        isParsingPresented = false
        isRawTextPresented = false
        selectedPhotoItem = nil
    }

    private var parsedTags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private func parsedCurrencyAmount(_ text: String) -> Double? {
        var value = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[^0-9,.\-]"#, with: "", options: .regularExpression)

        guard value.isEmpty == false, value != "-", value != ".", value != "," else {
            return nil
        }

        if value.contains(","), value.contains(".") {
            let commaIndex = value.lastIndex(of: ",") ?? value.startIndex
            let dotIndex = value.lastIndex(of: ".") ?? value.startIndex
            if commaIndex > dotIndex {
                value = value.replacingOccurrences(of: ".", with: "")
                value = value.replacingOccurrences(of: ",", with: ".")
            } else {
                value = value.replacingOccurrences(of: ",", with: "")
            }
        } else if let commaIndex = value.lastIndex(of: ",") {
            let decimalDigits = value.distance(from: value.index(after: commaIndex), to: value.endIndex)
            value = decimalDigits == 2
                ? value.replacingOccurrences(of: ",", with: ".")
                : value.replacingOccurrences(of: ",", with: "")
        }

        return Double(value)
    }

    private func analyzeReceipt(from image: UIImage) {
        isParsingPresented = true
        processingState = "Extracting Fields"
        parsingProgress = 0.2

        Task {
            do {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(150))
                parsingProgress = 0.55
                let draft = try await processReceiptUseCase.execute(image: image)
                parsingProgress = 0.9
                apply(draft: draft)
                recognizedMerchant = draft.merchant
                isParsingPresented = false
                processingState = "Ready For Review"
                parsingProgress = 1
                try? await Task.sleep(for: .milliseconds(120))
                isReviewPresented = true
            } catch {
                isParsingPresented = false
                processingState = "Needs Review"
                parsingProgress = 0
                appState.lastErrorMessage = error.localizedDescription
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

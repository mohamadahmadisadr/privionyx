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
    var stage: ReceiptCaptureStage = .idle
    /// Which stage of the pipeline is running, for the capture overlay. Replaces a
    /// `parsingProgress` fraction whose values were chosen to look plausible rather than
    /// measured — the pipeline cannot report a percentage, so it reports what it is doing.
    var parsingPhase: ReceiptProcessingPhase = .recognizing
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
            stage = .readyForReview
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
        && PrivionyxCurrencyParser.amount(from: amount).map { $0 > 0 } == true
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
        PrivionyxCurrencyParser.amount(from: amount)
    }

    var parsedSubtotal: Double? {
        PrivionyxCurrencyParser.amount(from: subtotal)
    }

    var parsedTax: Double? {
        PrivionyxCurrencyParser.amount(from: tax)
    }

    var parsedTip: Double? {
        PrivionyxCurrencyParser.amount(from: tip)
    }

    /// Everything the review screen says about the extraction, derived purely from the
    /// figures on the form. Lives in `ReceiptReviewAdvice` so it can be tested without a
    /// view model, a container and a Core Data stack behind it.
    var reviewAdvice: ReceiptReviewAdvice {
        ReceiptReviewAdvice(
            .init(
                isManualEntry: stage == .manualEntry,
                merchant: merchant,
                total: parsedAmount,
                subtotal: parsedSubtotal,
                tax: parsedTax,
                tip: parsedTip,
                rawTextLineCount: rawTextLineCount,
                derivedTotals: derivedTotals,
                totalsStatus: totalsStatus
            )
        )
    }

    var reviewHints: [String] { reviewAdvice.hints }
    var extractionTitle: String { reviewAdvice.title }
    var extractionMessage: String { reviewAdvice.message }

    var extractionIcon: String {
        reviewAdvice.confidence == .needsAttention ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
    }

    var extractionTint: Color {
        reviewAdvice.confidence == .needsAttention
            ? PrivionyxTheme.Colors.warning
            : PrivionyxTheme.Colors.success
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
        stage = .manualEntry
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
        guard let amountValue = PrivionyxCurrencyParser.amount(from: amount), amountValue > 0, trimmedMerchant.isEmpty == false else {
            appState.lastErrorMessage = "Merchant and amount are required."
            return
        }

        let draft = ReceiptDraft(
            id: editingReceiptID ?? UUID(),
            merchant: trimmedMerchant,
            amount: amountValue,
            subtotal: PrivionyxCurrencyParser.amount(from: subtotal),
            tax: PrivionyxCurrencyParser.amount(from: tax),
            tip: PrivionyxCurrencyParser.amount(from: tip),
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
            stage = .saved

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
        stage = .adjustingCrop

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
        stage = .idle
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

    private func analyzeReceipt(from image: UIImage) {
        isParsingPresented = true
        stage = .extracting
        parsingPhase = .recognizing

        Task {
            do {
                let draft = try await processReceiptUseCase.execute(image: image) { phase in
                    parsingPhase = phase
                }

                apply(draft: draft)
                recognizedMerchant = draft.merchant
                isParsingPresented = false
                stage = .readyForReview
                isReviewPresented = true
            } catch {
                isParsingPresented = false
                stage = .needsReview
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

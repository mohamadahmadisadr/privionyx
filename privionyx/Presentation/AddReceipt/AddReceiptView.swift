import Observation
import PhotosUI
import SwiftUI
import UIKit
import VisionKit

struct AddReceiptView: View {
    @State private var viewModel: AddReceiptViewModel
    @State private var isReviewExpanded = true
    private let onSaved: (() -> Void)?

    init(appState: PrivionyxAppState, initialDraft: ReceiptDraft? = nil, onSaved: (() -> Void)? = nil) {
        self.onSaved = onSaved
        _viewModel = State(initialValue: AddReceiptViewModel(appState: appState, initialDraft: initialDraft))
    }

    var body: some View {
        PrivionyxScreen(
            title: "Add Receipt",
            subtitle: "Scan a receipt, confirm the extracted fields, and save it locally."
        ) {
            if viewModel.isEditing {
                compactReviewCard
            } else {
                captureSection
            }
        }
        .photosPicker(isPresented: $viewModel.isPhotoPickerPresented, selection: $viewModel.selectedPhotoItem, matching: .images)
        .fullScreenCover(isPresented: $viewModel.isDocumentScannerPresented) {
            DocumentScannerView { image in
                viewModel.handleSelectedImage(image)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $viewModel.isCropEditorPresented) {
            if let cropImage = viewModel.cropSourceImage {
                ReceiptCropEditorView(
                    image: cropImage,
                    quadrilateral: $viewModel.cropQuadrilateral,
                    isDetecting: viewModel.isDetectingCrop,
                    onCancel: {
                        viewModel.cancelCropping()
                    },
                    onConfirm: {
                        viewModel.confirmCropAndAnalyze()
                    }
                )
            }
        }
        .sheet(isPresented: $viewModel.isReviewPresented, onDismiss: {
            if viewModel.didSaveSuccessfully {
                onSaved?()
            }
        }) {
            NavigationStack {
                ScrollView(showsIndicators: false) {
                    compactReviewCard
                        .padding(20)
                }
                .background(PrivionyxTheme.appBackground.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            viewModel.dismissReview()
                        }
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.isRawTextPresented) {
            RawExtractedTextView(text: viewModel.rawText)
        }
        .task(id: viewModel.selectedPhotoItem) {
            await viewModel.loadSelectedPhoto()
        }
        .overlay(alignment: .top) {
            if viewModel.showSavedToast {
                SavedToastView()
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay {
            if viewModel.isParsingPresented {
                ParsingReceiptView(progress: viewModel.parsingProgress)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.isEditing ? "Update receipt" : "Capture a receipt")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)

                    Text(viewModel.isEditing
                         ? "Replace the image or adjust the extracted fields, then save the updated version."
                         : "Scan a paper receipt or import a photo. Privionyx extracts the key fields and lets you review them before saving.")
                        .font(.subheadline)
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                }

                Spacer(minLength: 12)

                Image(systemName: "doc.text.viewfinder")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.accent)
                    .frame(width: 52, height: 52)
                    .background(PrivionyxTheme.Colors.surfaceMuted, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack(spacing: 10) {
                workflowStep("1", "Capture")
                workflowStep("2", "Review")
                workflowStep("3", "Save")
            }

            VStack(spacing: 12) {
                captureButton(
                    title: viewModel.isEditing ? "Scan New Receipt" : "Scan Receipt",
                    subtitle: "Use the document scanner for the best crop and OCR result.",
                    icon: "camera.fill"
                ) {
                    viewModel.presentCamera()
                }

                captureButton(
                    title: viewModel.isEditing ? "Import New Photo" : "Import Photo",
                    subtitle: "Choose a saved image and adjust the crop before extraction.",
                    icon: "photo.on.rectangle.angled"
                ) {
                    viewModel.presentPhotoPicker()
                }

                captureButton(
                    title: "Enter Manually",
                    subtitle: "Use this when a receipt is faded, handwritten, or unavailable.",
                    icon: "keyboard"
                ) {
                    viewModel.startManualEntry()
                }
            }

            if viewModel.hasReviewData == false {
                HStack(spacing: 10) {
                    Image(systemName: "checklist")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.accent)

                    Text("You stay in control: review merchant, amount, date, category, tax, tip, and notes before saving.")
                        .font(.footnote)
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                }
            }
        }
        .privionyxCardStyle()
    }

    private func workflowStep(_ number: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(PrivionyxTheme.Colors.accent, in: Circle())

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PrivionyxTheme.Colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(PrivionyxTheme.Colors.surfaceStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func captureButton(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.accent)
                    .frame(width: 46, height: 46)
                    .background(PrivionyxTheme.Colors.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
            }
            .padding(16)
            .background(PrivionyxTheme.Colors.surfaceStrong, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(PrivionyxTheme.Colors.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var compactReviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                previewThumb

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(PrivionyxTheme.Colors.accent)
                            .frame(width: 8, height: 8)
                        Text(viewModel.processingState)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PrivionyxTheme.Colors.accent)
                    }
                    Text(viewModel.merchant.isEmpty ? "Review receipt" : viewModel.merchant)
                        .font(.headline)
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                    Text(viewModel.amount.isEmpty ? "No amount detected" : "\(PrivionyxCurrencyFormatter.currentCurrencyCode) \(viewModel.amount)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                    Text(viewModel.displayCategoryName)
                        .font(.footnote)
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                }

                Spacer()
            }

            extractionStatusCard

            DisclosureGroup("Review details", isExpanded: $isReviewExpanded) {
                VStack(spacing: 12) {
                    Text("Check the detected fields and fix anything before saving.")
                        .font(.footnote)
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    editableField(title: "Merchant", prompt: "Merchant", value: $viewModel.merchant, isRequired: true)
                    editableField(title: "Amount", prompt: "0.00", value: $viewModel.amount, keyboardType: .decimalPad, isRequired: true)

                    HStack(spacing: 12) {
                        editableField(title: "Subtotal", prompt: "0.00", value: $viewModel.subtotal, keyboardType: .decimalPad)
                        editableField(title: "Tax", prompt: "0.00", value: $viewModel.tax, keyboardType: .decimalPad)
                    }

                    editableField(title: "Tip", prompt: "0.00", value: $viewModel.tip, keyboardType: .decimalPad)

                    totalsCheckSection
                    notesField

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Date")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

                        DatePicker("", selection: $viewModel.date, displayedComponents: .date)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(PrivionyxTheme.Colors.fieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ReceiptCategory.allCases) { category in
                                categoryChip(category)
                            }
                        }
                    }

                    editableField(title: "Custom Category", prompt: "Optional label", value: $viewModel.customCategoryName)
                    editableField(title: "Tags", prompt: "Comma separated", value: $viewModel.tagsText)

                    if viewModel.hasRawText {
                        Button {
                            viewModel.isRawTextPresented = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "text.viewfinder")
                                Text("View extracted text")
                                Spacer()
                                Text("\(viewModel.rawTextLineCount) lines")
                                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(PrivionyxTheme.Colors.accent)
                            .padding(14)
                            .background(PrivionyxTheme.Colors.surfaceStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if viewModel.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                        Text("Future receipts from this merchant will use the selected category.")
                            .font(.caption)
                            .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 12)
            }
            .tint(PrivionyxTheme.Colors.accent)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(PrivionyxTheme.Colors.ink)
            .onAppear {
                isReviewExpanded = true
            }

            HStack(spacing: 12) {
                if viewModel.canRetryOCR {
                    SecondaryActionButton(title: "Retry", systemImage: "arrow.clockwise") {
                        viewModel.retryOCR()
                    }
                }

                PrimaryActionButton(title: viewModel.isEditing ? "Update" : "Save", systemImage: viewModel.isEditing ? "square.and.arrow.down.fill" : "checkmark.circle.fill") {
                    Task {
                        await viewModel.saveReceipt()
                    }
                }
                .opacity(viewModel.canSave ? 1 : 0.55)
                .disabled(viewModel.canSave == false)
            }
        }
        .privionyxCardStyle()
    }

    private var previewThumb: some View {
        Group {
            if let image = viewModel.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(PrivionyxTheme.Colors.surfaceMuted)
                    .overlay {
                        Image(systemName: "doc.text.viewfinder")
                            .foregroundStyle(PrivionyxTheme.Colors.accent)
                    }
            }
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var extractionStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: viewModel.extractionIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(viewModel.extractionTint)
                    .frame(width: 30, height: 30)
                    .background(viewModel.extractionTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.extractionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                    Text(viewModel.extractionMessage)
                        .font(.caption)
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if viewModel.reviewHints.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.reviewHints, id: \.self) { hint in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(PrivionyxTheme.Colors.warning)
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            Text(hint)
                                .font(.caption)
                                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(PrivionyxTheme.Colors.surfaceStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func editableField(
        title: String,
        prompt: String,
        value: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        isRequired: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

                if isRequired {
                    Text("Required")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.accent)
                }
            }

            TextField(prompt, text: value)
                .keyboardType(keyboardType)
                .textFieldStyle(.plain)
                .padding(14)
                .foregroundStyle(PrivionyxTheme.Colors.fieldText)
                .background(PrivionyxTheme.Colors.fieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

            TextField("Add a note", text: $viewModel.notes, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .padding(14)
                .foregroundStyle(PrivionyxTheme.Colors.fieldText)
                .background(PrivionyxTheme.Colors.fieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var totalsCheckSection: some View {
        let enteredSubtotal = viewModel.parsedSubtotal
        let enteredTax = viewModel.parsedTax
        let enteredTip = viewModel.parsedTip
        let enteredAmount = viewModel.parsedAmount

        return VStack(alignment: .leading, spacing: 10) {
            Text("Totals Check")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

            InfoPill(title: "Entered Total", value: enteredAmount.map(PrivionyxCurrencyFormatter.string(for:)) ?? "--")

            if let enteredAmount, let enteredSubtotal {
                let expected = enteredSubtotal + (enteredTax ?? 0) + (enteredTip ?? 0)
                let delta = abs(expected - enteredAmount)
                HStack(spacing: 8) {
                    Image(systemName: delta < 0.02 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(delta < 0.02 ? PrivionyxTheme.Colors.success : PrivionyxTheme.Colors.warning)
                    Text(delta < 0.02 ? "Subtotal, tax, and tip match the total." : "Subtotal, tax, and tip differ from the total by \(PrivionyxCurrencyFormatter.string(for: delta)).")
                        .font(.caption)
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                }
            }
        }
    }

    private func categoryChip(_ category: ReceiptCategory) -> some View {
        let isSelected = viewModel.selectedCategory == category

        return Button {
            viewModel.selectedCategory = category
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                Text(category.rawValue)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isSelected ? .white : PrivionyxTheme.Colors.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isSelected ? PrivionyxTheme.Colors.accent : PrivionyxTheme.Colors.surfaceStrong,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(PrivionyxTheme.Colors.accent.opacity(isSelected ? 0 : 0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

@MainActor
@Observable
final class AddReceiptViewModel {
    @ObservationIgnored private let appState: PrivionyxAppState
    private let editingReceiptID: UUID?

    var merchant = ""
    var amount = ""
    var subtotal = ""
    var tax = ""
    var tip = ""
    var lineItems: [ReceiptLineItem] = []
    var date = Date.now
    var selectedCategory: ReceiptCategory = .shopping
    var customCategoryName = ""
    var tagsText = ""
    var rawText = ""
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

    init(appState: PrivionyxAppState, initialDraft: ReceiptDraft? = nil) {
        self.appState = appState
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
            lineItems: [],
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            status: .reviewed
        )

        do {
            didSaveSuccessfully = false
            try await appState.saveReceipt(draft)
            didSaveSuccessfully = true
            processingState = "Saved"
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

        let croppedImage = appState.cropReceiptImage(sourceImage, quadrilateral: cropQuadrilateral)
        let enhancedImage = appState.enhanceReceiptImage(croppedImage)

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
        lineItems = []
        date = draft.date
        selectedCategory = draft.category
        customCategoryName = draft.customCategoryName ?? ""
        tagsText = draft.tags.joined(separator: ", ")
        rawText = draft.rawText ?? ""
        notes = draft.notes
    }

    private func beginCropping(for image: UIImage) {
        let normalizedImage = appState.normalizeReceiptImage(image)
        cropSourceImage = normalizedImage
        cropQuadrilateral = .default
        isCropEditorPresented = true
        isDetectingCrop = true
        processingState = "Adjust Crop"

        Task {
            let detectedQuadrilateral = await appState.detectReceiptQuadrilateral(in: normalizedImage)
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
                let draft = try await appState.recognizeAndParseReceipt(from: image)
                parsingProgress = 0.9
                apply(draft: draft)
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

private struct SavedToastView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.white)
            Text("Receipt saved")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(PrivionyxTheme.Colors.accentStrong, in: Capsule())
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
    }
}

private struct ParsingReceiptView: View {
    let progress: Double

    var body: some View {
        ZStack {
            PrivionyxTheme.appBackground.ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.2)

                Text("Analyzing receipt")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)

                ProgressView(value: progress)
                    .tint(PrivionyxTheme.Colors.accent)
                    .frame(maxWidth: 220)

                Text("Privionyx is extracting the merchant, amount, and date.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    .frame(maxWidth: 260)
            }
            .padding(28)
            .background(PrivionyxTheme.Colors.surfaceStrong, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .interactiveDismissDisabled()
    }
}

private struct RawExtractedTextView: View {
    @Environment(\.dismiss) private var dismiss
    let text: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text.isEmpty ? "No extracted text is available." : text)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(18)
                    .background(PrivionyxTheme.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(20)
            }
            .background(PrivionyxTheme.appBackground.ignoresSafeArea())
            .navigationTitle("Extracted Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct ReceiptCropEditorView: View {
    let image: UIImage
    @Binding var quadrilateral: ReceiptQuadrilateral
    let isDetecting: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let imageFrame = fittedImageFrame(for: image.size, in: geometry.size)

                ZStack {
                    PrivionyxTheme.Colors.background.ignoresSafeArea()

                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)

                    CropOverlayView(quadrilateral: $quadrilateral, imageFrame: imageFrame)

                    if isDetecting {
                        VStack(spacing: 10) {
                            ProgressView()
                                .progressViewStyle(.circular)
                            Text("Detecting receipt edges")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            .navigationTitle("Adjust Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Use Crop", action: onConfirm)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func fittedImageFrame(for imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let widthScale = containerSize.width / imageSize.width
        let heightScale = containerSize.height / imageSize.height
        let scale = min(widthScale, heightScale)

        let fittedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: (containerSize.width - fittedSize.width) / 2,
            y: (containerSize.height - fittedSize.height) / 2
        )

        return CGRect(origin: origin, size: fittedSize)
    }
}

private struct CropOverlayView: View {
    @Binding var quadrilateral: ReceiptQuadrilateral
    let imageFrame: CGRect

    private let minimumHorizontalGap: CGFloat = 0.14
    private let minimumVerticalGap: CGFloat = 0.18
    @State private var dragStartQuadrilateral: ReceiptQuadrilateral?

    var body: some View {
        let topLeft = pointInImageFrame(quadrilateral.topLeft)
        let topRight = pointInImageFrame(quadrilateral.topRight)
        let bottomRight = pointInImageFrame(quadrilateral.bottomRight)
        let bottomLeft = pointInImageFrame(quadrilateral.bottomLeft)
        let polygon = [topLeft, topRight, bottomRight, bottomLeft]

        ZStack {
            Path { path in
                path.addRect(imageFrame)
                path.addLines(polygon + [topLeft])
                path.closeSubpath()
            }
            .fill(
                Color.black.opacity(0.5),
                style: FillStyle(eoFill: true)
            )

            Path { path in
                path.addLines(polygon + [topLeft])
            }
                .stroke(.white, lineWidth: 2)

            cropHandle(.topLeft, position: topLeft)
            cropHandle(.topRight, position: topRight)
            cropHandle(.bottomRight, position: bottomRight)
            cropHandle(.bottomLeft, position: bottomLeft)
        }
    }

    private func pointInImageFrame(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: imageFrame.minX + point.x * imageFrame.width,
            y: imageFrame.minY + (1 - point.y) * imageFrame.height
        )
    }

    private func cropHandle(_ corner: CropCorner, position: CGPoint) -> some View {
        Circle()
            .fill(.white)
            .frame(width: 22, height: 22)
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
            .position(position)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        moveCorner(corner, translation: value.translation)
                    }
                    .onEnded { _ in
                        dragStartQuadrilateral = nil
                    }
            )
    }

    private func moveCorner(_ corner: CropCorner, translation: CGSize) {
        guard imageFrame.width > 0, imageFrame.height > 0 else { return }
        let startQuadrilateral = dragStartQuadrilateral ?? quadrilateral
        if dragStartQuadrilateral == nil {
            dragStartQuadrilateral = startQuadrilateral
        }

        let updatedPoint = CGPoint(
            x: min(max(startQuadrilateral[corner].x + (translation.width / imageFrame.width), 0.02), 0.98),
            y: min(max(startQuadrilateral[corner].y - (translation.height / imageFrame.height), 0.02), 0.98)
        )

        var updatedQuadrilateral = startQuadrilateral
        updatedQuadrilateral[corner] = updatedPoint
        quadrilateral = constrained(updatedQuadrilateral)
    }

    private func constrained(_ quad: ReceiptQuadrilateral) -> ReceiptQuadrilateral {
        var result = quad

        result.topLeft.x = clamp(result.topLeft.x, min: 0.02, max: result.topRight.x - minimumHorizontalGap)
        result.bottomLeft.x = clamp(result.bottomLeft.x, min: 0.02, max: result.bottomRight.x - minimumHorizontalGap)

        result.topRight.x = clamp(result.topRight.x, min: result.topLeft.x + minimumHorizontalGap, max: 0.98)
        result.bottomRight.x = clamp(result.bottomRight.x, min: result.bottomLeft.x + minimumHorizontalGap, max: 0.98)

        result.topLeft.y = clamp(result.topLeft.y, min: result.bottomLeft.y + minimumVerticalGap, max: 0.98)
        result.topRight.y = clamp(result.topRight.y, min: result.bottomRight.y + minimumVerticalGap, max: 0.98)

        result.bottomLeft.y = clamp(result.bottomLeft.y, min: 0.02, max: result.topLeft.y - minimumVerticalGap)
        result.bottomRight.y = clamp(result.bottomRight.y, min: 0.02, max: result.topRight.y - minimumVerticalGap)

        return result
    }

    private func clamp(_ value: CGFloat, min lowerBound: CGFloat, max upperBound: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

private enum CropCorner {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft
}

private extension ReceiptQuadrilateral {
    subscript(corner: CropCorner) -> CGPoint {
        get {
            switch corner {
            case .topLeft: topLeft
            case .topRight: topRight
            case .bottomRight: bottomRight
            case .bottomLeft: bottomLeft
            }
        }
        set {
            switch corner {
            case .topLeft: topLeft = newValue
            case .topRight: topRight = newValue
            case .bottomRight: bottomRight = newValue
            case .bottomLeft: bottomLeft = newValue
            }
        }
    }
}

#Preview {
    AddReceiptView(appState: PrivionyxAppState(container: .live(inMemory: true)))
}

private struct DocumentScannerView: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let completion: (UIImage?) -> Void

        init(completion: @escaping (UIImage?) -> Void) {
            self.completion = completion
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let image = scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil
            completion(image)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            completion(nil)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            completion(nil)
        }
    }
}

import PhotosUI
import SwiftUI
import UIKit

struct AddReceiptView: View {
    @State private var viewModel: AddReceiptViewModel
    /// The review sheet opens on the compact result summary and swaps to the full
    /// editor only when the user asks to correct something.
    @State private var isEditingDetails = false
    @State private var reviewDetent: PresentationDetent = .medium
    /// Set by "Retake" so the camera reopens once the sheet has finished dismissing.
    @State private var isRetakeRequested = false
    private let onSaved: (() -> Void)?

    init(appState: PrivionyxAppState, initialDraft: ReceiptDraft? = nil, onSaved: (() -> Void)? = nil) {
        self.onSaved = onSaved
        _viewModel = State(initialValue: appState.container.makeAddReceiptViewModel(appState: appState, initialDraft: initialDraft))
    }

    var body: some View {
        GlassScreen(
            title: "Scan Receipt",
            subtitle: "Capture, import, or enter a receipt, then review before saving."
        ) {
            if viewModel.isEditing {
                reviewEditor
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
                    onCancel: { viewModel.cancelCropping() },
                    onConfirm: { viewModel.confirmCropAndAnalyze() }
                )
            }
        }
        .sheet(isPresented: $viewModel.isReviewPresented, onDismiss: {
            isEditingDetails = false
            reviewDetent = .medium

            if viewModel.didSaveSuccessfully {
                onSaved?()
            }
            if isRetakeRequested {
                isRetakeRequested = false
                viewModel.presentCamera()
            }
        }) {
            reviewSheet
        }
        .sheet(isPresented: $viewModel.isRawTextPresented) {
            RawExtractedTextView(text: viewModel.rawText)
        }
        .task(id: viewModel.selectedPhotoItem) {
            await viewModel.loadSelectedPhoto()
        }
        // Editing has no review sheet whose dismissal would fire `onSaved`, so close the
        // editor as soon as the update succeeds.
        .onChange(of: viewModel.didSaveSuccessfully) { _, saved in
            if saved, viewModel.isEditing {
                onSaved?()
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.showSavedToast {
                SavedToastView()
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if viewModel.isParsingPresented {
                ParsingReceiptView(phase: viewModel.parsingPhase)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .sheet(item: $viewModel.pendingDownloadPrompt) { prompt in
            GemmaDownloadPromptView(
                prompt: prompt,
                suppressFuturePrompts: $viewModel.suppressFutureEnginePrompts,
                onAccept: { viewModel.acceptDownloadPrompt() },
                onDecline: { viewModel.declineDownloadPrompt() }
            )
        }
        .overlay {
            if viewModel.isGemmaDownloadInProgress {
                GemmaDownloadProgressView(
                    progress: viewModel.gemmaDownloadProgress,
                    sizeDescription: viewModel.gemmaDownloadSizeDescription,
                    onCancel: { viewModel.cancelGemmaDownload() }
                )
                .transition(.opacity)
                .zIndex(20)
            }
        }
    }

    // MARK: - Capture

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose how to add your receipt.")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)

                Text("Scan it, import a photo, or enter the details manually.")
                    .font(.system(size: 13))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
            }

            VStack(spacing: 10) {
                captureButton(
                    title: viewModel.isEditing ? "Scan New Receipt" : "Scan Receipt",
                    subtitle: "Use the camera scanner.",
                    icon: "camera.fill"
                ) {
                    viewModel.presentCamera()
                }

                captureButton(
                    title: viewModel.isEditing ? "Import New Photo" : "Import Photo",
                    subtitle: "Choose a photo from your library.",
                    icon: "photo.on.rectangle.angled"
                ) {
                    viewModel.presentPhotoPicker()
                }

                captureButton(
                    title: "Enter Manually",
                    subtitle: "Add the details yourself.",
                    icon: "keyboard"
                ) {
                    viewModel.startManualEntry()
                }
            }

            if viewModel.hasReviewData == false {
                Text("You can review and edit the extracted fields before anything is saved.")
                    .font(.system(size: 12))
                    .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
            }
        }
        .privionyxCardStyle()
    }

    private func captureButton(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                GlassIconTile(systemImage: icon, size: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)

                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
            }
            .padding(14)
            .contentShape(Rectangle())
            .privionyxGlass(cornerRadius: 16, strong: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Review sheet

    private var reviewSheet: some View {
        ZStack {
            PrivionyxTheme.appBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                if isEditingDetails {
                    reviewEditor
                        .padding(20)
                } else {
                    ReceiptResultSheet(
                        viewModel: viewModel,
                        onRetake: {
                            isRetakeRequested = true
                            viewModel.dismissReview()
                        },
                        onEditDetails: {
                            isEditingDetails = true
                            reviewDetent = .large
                        },
                        onSave: {
                            Task { await viewModel.saveReceipt() }
                        }
                    )
                    .padding(20)
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $reviewDetent)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Review editor

    private var reviewEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.merchant.isEmpty ? "Review receipt" : viewModel.merchant)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)

                Text(viewModel.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 13))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
            }

            extractionStatusCard

            if viewModel.previewImage != nil {
                previewImageSection
            }

            if viewModel.lineItems.isEmpty == false {
                lineItemsSection
            }

            fieldsSection
            categorySection

            if viewModel.hasRawText {
                rawTextButton
            }

            actionRow
        }
        .privionyxCardStyle()
    }

    private var extractionStatusCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: viewModel.extractionIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(viewModel.extractionTint)
                    .frame(width: 30, height: 30)
                    .background(viewModel.extractionTint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.extractionTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)

                    Text(viewModel.extractionMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if viewModel.reviewHints.isEmpty == false {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(viewModel.reviewHints, id: \.self) { hint in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(PrivionyxTheme.Colors.warning)
                                .frame(width: 5, height: 5)
                                .padding(.top, 5)

                            Text(hint)
                                .font(.system(size: 12))
                                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .privionyxGlass(cornerRadius: 14, strong: true)
    }

    @ViewBuilder
    private var previewImageSection: some View {
        if let image = viewModel.previewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(PrivionyxTheme.Colors.glassStroke, lineWidth: 1)
                )
        }
    }

    private var lineItemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GlassSectionTitle("Line Items", actionTitle: "\(viewModel.lineItems.count)")

            VStack(spacing: 9) {
                ForEach(viewModel.lineItems) { item in
                    GlassValueRow(
                        title: item.quantity.map { "\($0)× \(item.name)" } ?? item.name,
                        value: PrivionyxCurrencyFormatter.string(for: item.amount)
                    )
                }
            }
            .padding(13)
            .privionyxGlass(cornerRadius: 14, strong: true)
        }
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassTextField(title: "Merchant", prompt: "Merchant", text: $viewModel.merchant, isRequired: true)
            GlassTextField(title: "Amount", prompt: "0.00", text: $viewModel.amount, keyboardType: .decimalPad, isRequired: true)

            HStack(spacing: 12) {
                GlassTextField(title: "Subtotal", prompt: "0.00", text: $viewModel.subtotal, keyboardType: .decimalPad)
                GlassTextField(title: "Tax", prompt: "0.00", text: $viewModel.tax, keyboardType: .decimalPad)
            }

            GlassTextField(title: "Tip", prompt: "0.00", text: $viewModel.tip, keyboardType: .decimalPad)

            totalsCheck

            GlassTextField(title: "Note", prompt: "Add a note", text: $viewModel.notes, axis: .vertical, lineLimit: 2...4)

            VStack(alignment: .leading, spacing: 7) {
                Text("Date")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

                DatePicker("", selection: $viewModel.date, displayedComponents: .date)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
                    .privionyxGlass(cornerRadius: 14, strong: true)
            }

            GlassTextField(title: "Custom Category", prompt: "Optional label", text: $viewModel.customCategoryName)
            GlassTextField(title: "Tags", prompt: "Comma separated", text: $viewModel.tagsText)
        }
    }

    @ViewBuilder
    private var totalsCheck: some View {
        let enteredAmount = viewModel.parsedAmount
        let enteredSubtotal = viewModel.parsedSubtotal

        if let enteredAmount, let enteredSubtotal {
            let expected = enteredSubtotal + (viewModel.parsedTax ?? 0) + (viewModel.parsedTip ?? 0)
            let delta = abs(expected - enteredAmount)
            let matches = delta < 0.02

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: matches ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(matches ? PrivionyxTheme.Colors.success : PrivionyxTheme.Colors.warning)

                Text(matches
                     ? "Subtotal, tax, and tip match the total."
                     : "Subtotal, tax, and tip differ from the total by \(PrivionyxCurrencyFormatter.string(for: delta)).")
                    .font(.system(size: 12))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(12)
            .privionyxGlass(cornerRadius: 12)
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReceiptCategory.allCases) { category in
                        GlassChip(
                            title: category.rawValue,
                            systemImage: category.icon,
                            isSelected: viewModel.selectedCategory == category
                        ) {
                            viewModel.selectedCategory = category
                        }
                    }
                }
                .padding(.horizontal, 1)
            }

            if viewModel.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                Text("Future receipts from this merchant will use the selected category.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
            }
        }
    }

    private var rawTextButton: some View {
        Button {
            viewModel.isRawTextPresented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "text.viewfinder")
                Text("View extracted text")
                Spacer()
                Text("\(viewModel.rawTextLineCount) lines")
                    .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(PrivionyxTheme.Colors.accent)
            .padding(13)
            .privionyxGlass(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if viewModel.canRetryOCR {
                GlassSecondaryButton(title: "Retry") {
                    viewModel.retryOCR()
                }
            }

            GlassPrimaryButton(title: viewModel.isEditing ? "Update" : "Save") {
                Task { await viewModel.saveReceipt() }
            }
            .opacity(viewModel.canSave ? 1 : 0.5)
            .disabled(viewModel.canSave == false)
        }
    }
}

#Preview {
    AddReceiptView(appState: PrivionyxAppState(container: .preview))
}

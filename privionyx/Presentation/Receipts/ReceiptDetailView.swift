import SwiftUI
import UIKit

struct ReceiptDetailView: View {
    @Environment(PrivionyxAppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let receipt: ReceiptItem
    @State private var isShareSheetPresented = false
    @State private var isImagePreviewPresented = false
    @State private var isEditPresented = false
    @State private var isDeleteAlertPresented = false

    var body: some View {
        GlassScreen(wrapsInNavigationStack: false) {
            header
        } content: {
            summaryCard
            imageSection
            detailsSection
            if receipt.lineItems.isEmpty == false {
                lineItemsSection
            }
            deleteButton
        }
        .sheet(isPresented: $isShareSheetPresented) {
            ActivityViewController(activityItems: shareItems)
        }
        .sheet(isPresented: $isEditPresented) {
            AddReceiptView(
                appState: appState,
                initialDraft: ReceiptDraft(item: receipt),
                onSaved: {
                    isEditPresented = false
                    dismiss()
                }
            )
        }
        .fullScreenCover(isPresented: $isImagePreviewPresented) {
            ReceiptImagePreview(
                image: receipt.imageData.flatMap(UIImage.init(data:)),
                onClose: { isImagePreviewPresented = false }
            )
        }
        .alert("Delete Receipt?", isPresented: $isDeleteAlertPresented) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await appState.deleteReceipt(id: receipt.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This receipt will be removed from local storage.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            GlassCircleButton(systemImage: "chevron.left", accessibilityTitle: "Back") {
                dismiss()
            }

            Spacer()

            GlassCircleButton(systemImage: "pencil", accessibilityTitle: "Edit receipt") {
                isEditPresented = true
            }

            GlassCircleButton(systemImage: "square.and.arrow.up", accessibilityTitle: "Share receipt") {
                isShareSheetPresented = true
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                InitialTile(
                    text: receipt.merchant,
                    tint: PrivionyxTheme.Colors.accent,
                    size: 44,
                    foreground: PrivionyxTheme.Colors.onAccent
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(receipt.merchant)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(receipt.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12.5))
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                }

                Spacer(minLength: 8)
            }

            HStack(spacing: 8) {
                CategoryTag(title: receipt.displayCategoryName)
                GlassBadge(title: receipt.status.rawValue, tint: statusTint)
                Spacer(minLength: 8)
                Text(PrivionyxCurrencyFormatter.string(for: receipt.amount))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .privionyxCardStyle()
    }

    // MARK: - Sections

    @ViewBuilder
    private var imageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionTitle("Receipt Image", actionTitle: receipt.imageData == nil ? nil : "Tap to view")

            if let imageData = receipt.imageData, let uiImage = UIImage(data: imageData) {
                Button {
                    isImagePreviewPresented = true
                } label: {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .privionyxGlass(cornerRadius: 16)
                        .overlay(alignment: .bottomTrailing) {
                            GlassBadge(title: "Preview", systemImage: "arrow.up.left.and.arrow.down.right")
                                .padding(12)
                        }
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
                    Text("No receipt image available")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .privionyxGlass(cornerRadius: 16)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionTitle("Details")

            VStack(spacing: 11) {
                GlassValueRow(title: "Merchant", value: receipt.merchant)
                if let subtotal = receipt.subtotal {
                    GlassValueRow(title: "Subtotal", value: PrivionyxCurrencyFormatter.string(for: subtotal))
                }
                if let tax = receipt.tax {
                    GlassValueRow(title: "Tax", value: PrivionyxCurrencyFormatter.string(for: tax))
                }
                if let tip = receipt.tip {
                    GlassValueRow(title: "Tip", value: PrivionyxCurrencyFormatter.string(for: tip))
                }
                GlassValueRow(title: "Date", value: receipt.date.formatted(date: .abbreviated, time: .omitted))
                GlassValueRow(title: "Category", value: receipt.displayCategoryName)
                if receipt.tags.isEmpty == false {
                    GlassValueRow(title: "Tags", value: receipt.tags.joined(separator: ", "))
                }
                if receipt.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    GlassValueRow(title: "Notes", value: receipt.notes)
                }

                Divider().overlay(PrivionyxTheme.Colors.separator)

                GlassValueRow(
                    title: "Total",
                    value: PrivionyxCurrencyFormatter.string(for: receipt.amount),
                    isEmphasized: true
                )
            }
            .privionyxCardStyle()
        }
    }

    private var lineItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionTitle("Line Items", actionTitle: "\(receipt.lineItems.count)")

            GlassRowGroup {
                ForEach(Array(receipt.lineItems.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Text(item.quantity.map { "\($0)× \(item.name)" } ?? item.name)
                            .font(.system(size: 14))
                            .foregroundStyle(PrivionyxTheme.Colors.ink)

                        Spacer(minLength: 12)

                        Text(PrivionyxCurrencyFormatter.string(for: item.amount))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    if index < receipt.lineItems.count - 1 {
                        GlassRowDivider()
                    }
                }
            }
        }
    }

    private var deleteButton: some View {
        Button {
            isDeleteAlertPresented = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                Text("Delete Receipt")
            }
            .font(.system(size: 14.5, weight: .bold))
            .foregroundStyle(PrivionyxTheme.Colors.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .privionyxGlass(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var statusTint: Color {
        switch receipt.status {
        case .scanned:
            PrivionyxTheme.Colors.accent
        case .reviewed:
            PrivionyxTheme.Colors.success
        case .flagged:
            PrivionyxTheme.Colors.warning
        }
    }

    private var shareItems: [Any] {
        var items: [Any] = [shareSummary]

        if let imageData = receipt.imageData, let image = UIImage(data: imageData) {
            items.insert(image, at: 0)
        }

        return items
    }

    private var shareSummary: String {
        [
            receipt.merchant,
            "Amount: \(PrivionyxCurrencyFormatter.string(for: receipt.amount))",
            "Date: \(receipt.date.formatted(date: .abbreviated, time: .omitted))",
            "Category: \(receipt.displayCategoryName)"
        ]
        .joined(separator: "\n")
    }
}

private struct ReceiptImagePreview: View {
    let image: UIImage?
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            if let image {
                ZoomableScrollView {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                }
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .padding()
        }
    }
}

#Preview {
    NavigationStack {
        ReceiptDetailView(
            receipt: ReceiptItem(
                id: UUID(),
                merchant: "Preview Receipt",
                amount: 24.80,
                subtotal: 21.50,
                tax: 3.30,
                tip: nil,
                date: .now,
                category: .shopping,
                customCategoryName: "Office Supplies",
                tags: ["Work", "Claim"],
                imagePath: nil,
                imageData: nil,
                rawText: "PREVIEW\nTOTAL 24.80",
                lineItems: [],
                notes: "Stored locally",
                status: .reviewed
            )
        )
        .environment(PrivionyxAppState(container: .preview))
    }
}

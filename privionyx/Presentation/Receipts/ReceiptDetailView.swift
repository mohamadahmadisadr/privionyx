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
        PrivionyxScreen(
            title: "Receipt Detail",
            subtitle: "Saved image and extracted fields for a single local receipt."
        ) {
            headerSection
            receiptImageSection
            metadataSection
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
                onClose: {
                    isImagePreviewPresented = false
                }
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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                        .frame(width: 44, height: 44)
                        .background(PrivionyxTheme.Colors.surfaceStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")

                Spacer()

                Button {
                    isEditPresented = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                        .frame(width: 44, height: 44)
                        .background(PrivionyxTheme.Colors.surfaceStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit receipt")

                Button {
                    isShareSheetPresented = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                        .frame(width: 44, height: 44)
                        .background(PrivionyxTheme.Colors.surfaceStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share receipt")
            }

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: receipt.category.icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.accent)
                    .frame(width: 54, height: 54)
                    .background(PrivionyxTheme.Colors.surfaceMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(receipt.merchant)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Text(receipt.displayCategoryName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.accent)

                    Text(receipt.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.footnote)
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                }

                Spacer(minLength: 8)

                Text(PrivionyxCurrencyFormatter.string(for: receipt.amount))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .privionyxCardStyle()
    }

    private var receiptImageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Receipt Image", actionTitle: receipt.imageData == nil ? nil : "Tap To View")

            if let imageData = receipt.imageData, let uiImage = UIImage(data: imageData) {
                Button {
                    isImagePreviewPresented = true
                } label: {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PrivionyxTheme.Colors.surfaceStrong)
                    .frame(height: 220)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                            Text("No receipt image available")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(PrivionyxTheme.Colors.ink)
                        }
                    }
            }
        }
        .privionyxCardStyle()
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Extracted Data", actionTitle: receipt.status.rawValue)

            VStack(spacing: 14) {
                detailRow(title: "Merchant", value: receipt.merchant)
                if let subtotal = receipt.subtotal {
                    detailRow(title: "Subtotal", value: PrivionyxCurrencyFormatter.string(for: subtotal))
                }
                if let tax = receipt.tax {
                    detailRow(title: "Tax", value: PrivionyxCurrencyFormatter.string(for: tax))
                }
                if let tip = receipt.tip {
                    detailRow(title: "Tip", value: PrivionyxCurrencyFormatter.string(for: tip))
                }
                detailRow(title: "Amount", value: PrivionyxCurrencyFormatter.string(for: receipt.amount))
                detailRow(title: "Date", value: receipt.date.formatted(date: .abbreviated, time: .omitted))
                detailRow(title: "Category", value: receipt.displayCategoryName)
                if receipt.tags.isEmpty == false {
                    detailRow(title: "Tags", value: receipt.tags.joined(separator: ", "))
                }
                if receipt.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    detailRow(title: "Notes", value: receipt.notes)
                }
            }

            HStack(spacing: 12) {
                SecondaryActionButton(title: "Delete", systemImage: "trash") {
                    isDeleteAlertPresented = true
                }
            }
        }
        .privionyxCardStyle()
    }


    private func detailRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                .frame(width: 88, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .foregroundStyle(PrivionyxTheme.Colors.ink)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
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

#Preview {
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
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
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
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .padding()
        }
    }
}

private struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(hostingController: UIHostingController(rootView: content))
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 4
        scrollView.minimumZoomScale = 1
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.backgroundColor = .clear

        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear

        scrollView.addSubview(hostedView)

        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostedView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hostedView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let hostingController: UIHostingController<Content>

        init(hostingController: UIHostingController<Content>) {
            self.hostingController = hostingController
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }
    }
}

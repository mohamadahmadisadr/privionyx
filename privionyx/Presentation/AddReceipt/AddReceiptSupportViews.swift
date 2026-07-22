import SwiftUI

struct SavedToastView: View {
    var body: some View {
        GlassToast(text: "Receipt saved")
    }
}

struct ParsingReceiptView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .overlay(.ultraThinMaterial)

            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.1)

                Text("Analyzing receipt…")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)

                ProgressView(value: progress)
                    .frame(width: 180)
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 26)
            .privionyxGlass(cornerRadius: 18, strong: true)
        }
        .interactiveDismissDisabled()
    }
}

struct RawExtractedTextView: View {
    @Environment(\.dismiss) private var dismiss
    let text: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Raw OCR Output")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)

                    Text(text.isEmpty ? "No extracted text is available." : text)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(18)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
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

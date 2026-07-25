import SwiftUI

struct SavedToastView: View {
    var body: some View {
        GlassToast(text: "Receipt saved")
    }
}

/// Shown over the capture screen while a photograph is turned into a draft.
///
/// The determinate bar this used to carry was driven by hard-coded fractions, and the work
/// it sat above cannot report a percentage — so it said nothing true and made the wait look
/// longer than it was. The spinner conveys "working"; the phase says what is being worked on.
struct ParsingReceiptView: View {
    let phase: ReceiptProcessingPhase

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .overlay(.ultraThinMaterial)

            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.1)

                Text(phase.label)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                    .animation(.easeInOut(duration: 0.2), value: phase)
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 26)
            .frame(minWidth: 200)
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

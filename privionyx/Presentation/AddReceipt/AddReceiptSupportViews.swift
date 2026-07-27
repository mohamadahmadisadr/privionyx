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

/// Offers the Gemma download before the receipt is read.
///
/// A sheet rather than an `alert` for one reason: the checkbox. SwiftUI alerts take buttons
/// and nothing else, and "don't ask again" is the part that keeps this from becoming a nag —
/// so the question that needs it cannot be an alert.
struct GemmaDownloadPromptView: View {
    let prompt: GemmaDownloadPrompt
    @Binding var suppressFuturePrompts: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prompt.title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(PrivionyxTheme.Colors.ink)

            Text(prompt.message)
                .font(.system(size: 14))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $suppressFuturePrompts) {
                Text("Don't ask again")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
            }
            .toggleStyle(.switch)
            // Says what ticking the box actually commits to. "Don't ask again" alone does
            // not distinguish "always do this" from "never offer this", and the answer
            // depends on which button is then pressed.
            Text("Your choice is remembered. You can change it in Settings.")
                .font(.system(size: 12))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

            VStack(spacing: 10) {
                Button(action: onAccept) {
                    Text(prompt.acceptTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onDecline) {
                    Text(prompt.declineTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.top, 2)
        }
        // Top inset is larger than the rest: a sheet with no drag indicator starts its
        // content flush against the edge, which left the title looking clipped to the top
        // of the card rather than placed on it.
        .padding(.horizontal, 24)
        .padding(.top, 34)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.hidden)
        // Dismissing by swipe would leave the receipt unread with no decision recorded, so
        // the two buttons are the only ways out.
        .interactiveDismissDisabled()
    }
}

/// Shown while the Gemma weights download, after the user has asked for a better read of
/// the receipt they are looking at.
///
/// Determinate, unlike `ParsingReceiptView` — a download is the one part of this pipeline
/// that genuinely knows how far along it is, and a multi-gigabyte wait with no percentage
/// is indistinguishable from a hang. Cancelling is always offered for the same reason.
struct GemmaDownloadProgressView: View {
    let progress: Double
    let sizeDescription: String
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .overlay(.ultraThinMaterial)

            VStack(spacing: 14) {
                Text("Downloading Gemma")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 220)

                Text("\(Int(progress * 100))% of \(sizeDescription)")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    .monospacedDigit()

                Text("Your receipt will be re-read when this finishes.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    .multilineTextAlignment(.center)

                Button("Cancel", role: .cancel, action: onCancel)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.top, 2)
            }
            .padding(.vertical, 22)
            .padding(.horizontal, 26)
            .frame(minWidth: 240)
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

import SwiftUI

/// What the assistant does with a user's receipts, stated in the app rather than only in the
/// privacy policy.
///
/// App Review rejected 1.0 (9) under guidelines 5.1.1(i) and 5.1.2(i), reading the Assistant
/// tab as sharing personal data with a third-party AI service. Nothing is shared: all three
/// engines run on-device, and the only request the app ever makes to Hugging Face is a
/// one-way GET for the Gemma model file. The rejection was still earned — the tab promised an
/// "AI Assistant" that "understands every receipt you scan" and said nothing about where that
/// understanding happened, and the disclosure that did exist was two screens away in Settings
/// and Acknowledgements.
///
/// So this sheet is shown once, the first time the Assistant tab is opened, and stays
/// reachable from the header afterwards. It deliberately is not a consent gate: asking
/// permission to share data that is never shared would misinform the user in the opposite
/// direction. It answers the three questions the guideline asks — what data, to whom, and
/// where it goes — and the answer to the third is "nowhere".
struct AssistantPrivacyDisclosure: View {
    let backend: AssistantBackend
    let onDismiss: () -> Void

    /// Set once the sheet has been shown, so it does not reappear on every visit.
    /// Read by `AssistantView`, written here, because being seen is what marks it seen.
    static let seenKey = "privionyx.assistantDisclosureSeen"

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                PrivionyxTheme.appBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        badge

                        Text("Your receipts stay on this iPhone")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(PrivionyxTheme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("The assistant answers questions about your spending. Here is exactly what it reads, what does the reading, and what leaves your device.")
                            .font(.system(size: 14))
                            .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)

                        section(
                            icon: "doc.text.magnifyingglass",
                            title: "What it reads",
                            body: "The receipts already saved in Privionyx — merchant names, amounts including taxes, dates, categories, line items, notes, and the text recognized from your receipt photos. Plus the question you type."
                        )

                        section(
                            icon: backend.icon,
                            title: "What does the reading",
                            body: backend.processorDescription
                        )

                        section(
                            icon: "wifi.slash",
                            title: "What leaves your device",
                            body: "Nothing. Your receipts and your questions are not sent to Privionyx, to any AI or cloud service, or to any other company — there is no server to send them to, and the app contains no code that could. It works in Airplane Mode."
                        )

                        Text("The one network request the assistant can make is downloading the optional Gemma model file from Hugging Face, if you choose that engine in Settings. It is a plain file download and carries no receipt data.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
                            .fixedSize(horizontal: false, vertical: true)

                        Link(destination: URL(string: "https://sadr.dev/privionyx-app/privacy/")!) {
                            HStack(spacing: 5) {
                                Text("Read the full privacy policy")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PrivionyxTheme.Colors.accent)
                        }

                        GlassPrimaryButton(title: "Got it") {
                            onDismiss()
                            dismiss()
                        }
                        .padding(.top, 2)
                    }
                    .padding(20)
                    // Clears the home indicator, which the primary button otherwise sits under.
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
        }
    }

    private var badge: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.iphone")
                .font(.system(size: 11, weight: .bold))
            Text("On-device")
                .font(.system(size: 11.5, weight: .heavy))
        }
        .foregroundStyle(PrivionyxTheme.Colors.accent)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(PrivionyxTheme.Colors.accentSoft, in: Capsule())
    }

    private func section(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PrivionyxTheme.Colors.accent)
                .frame(width: 30, height: 30)
                .background(PrivionyxTheme.Colors.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)

                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .privionyxGlass(cornerRadius: 16)
    }
}

#Preview {
    AssistantPrivacyDisclosure(backend: .localGemma) {}
}

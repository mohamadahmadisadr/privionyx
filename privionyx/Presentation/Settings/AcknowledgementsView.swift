import SwiftUI

/// One third-party component the app ships or downloads, and the terms it comes under.
///
/// Apache-2.0 section 4 asks for the licence to travel with the work and for attribution
/// notices to be retained. Neither is satisfied by the licence sitting in a repository the
/// user never visits, so it is reproduced here — in full, from `Apache-2.0.txt` in the bundle,
/// rather than linked. A licence behind a network request is not a licence the user has.
nonisolated struct Acknowledgement: Identifiable, Sendable {
    let id: String
    let name: String
    /// Who to credit, as they ask to be credited.
    let author: String
    let licence: String
    /// What it does here, in one sentence — an acknowledgements screen that only lists names
    /// tells the reader nothing about what they are running.
    let role: String
    let homepage: URL?

    static let all: [Acknowledgement] = [
        Acknowledgement(
            id: "gemma",
            name: "Gemma 4 E2B",
            author: "Google LLC",
            licence: "Apache License 2.0",
            role: """
                The optional on-device assistant. Downloaded from Hugging Face at the user's \
                request and run locally — no prompt or receipt ever leaves the device.
                """,
            homepage: URL(string: "https://huggingface.co/google/gemma-4-E2B-it")
        ),
        Acknowledgement(
            id: "litert-lm",
            name: "LiteRT-LM",
            author: "Google LLC",
            licence: "Apache License 2.0",
            role: "The runtime that loads and runs Gemma on the device's CPU or GPU.",
            homepage: URL(string: "https://ai.google.dev/edge/litert-lm/overview")
        )
    ]
}

struct AcknowledgementsView: View {
    var body: some View {
        GlassScreen(
            title: "Acknowledgements",
            subtitle: "Privionyx is built on work other people gave away.",
            wrapsInNavigationStack: false
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Acknowledgement.all) { acknowledgement in
                    card(for: acknowledgement)
                }

                GlassEyebrow("Licence text")
                licenceCard
            }
        }
    }

    private func card(for acknowledgement: Acknowledgement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(acknowledgement.name)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(PrivionyxTheme.Colors.ink)

            Text("\(acknowledgement.author) · \(acknowledgement.licence)")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)

            Text(acknowledgement.role)
                .font(.system(size: 13))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            if let homepage = acknowledgement.homepage {
                Link(destination: homepage) {
                    HStack(spacing: 4) {
                        Text(homepage.host ?? homepage.absoluteString)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .privionyxGlass(cornerRadius: 16)
    }

    private var licenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Both components above are licensed under the Apache License, Version 2.0, reproduced in full below.")
                .font(.system(size: 13))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            // Monospaced and horizontally scrollable: the licence is a fixed-width document
            // and reflowing it would misalign the section numbering it refers to itself by.
            ScrollView(.horizontal, showsIndicators: false) {
                Text(Self.apacheLicenceText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .privionyxGlass(cornerRadius: 16)
    }

    /// Read once. Missing is not a crash — a shipped app should not die because a text file
    /// was dropped from the bundle — but it does say so plainly rather than showing nothing,
    /// because a licence screen with no licence on it is the failure worth noticing.
    static let apacheLicenceText: String = {
        guard let url = Bundle.main.url(forResource: "Apache-2.0", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "The licence text could not be loaded. It is available at https://www.apache.org/licenses/LICENSE-2.0"
        }
        return text
    }()
}

#Preview {
    NavigationStack {
        AcknowledgementsView()
    }
}

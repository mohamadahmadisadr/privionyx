import SwiftUI

struct SettingsView: View {
    @Environment(PrivionyxAppState.self) private var appState
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode: AppearanceMode = .system
    @AppStorage(AssistantBackend.storageKey) private var assistantBackend: AssistantBackend = .fallback
    @State private var assistantAvailability: [AssistantBackend: AssistantAvailability] = [:]

    var body: some View {
        NavigationStack {
            ZStack {
                PrivionyxTheme.appBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Settings")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(PrivionyxTheme.Colors.ink)
                            .padding(.bottom, 2)

                        GlassEyebrow("Appearance")
                        appearanceCard

                        GlassEyebrow("Assistant")
                        assistantCard

                        GlassEyebrow("About")
                        aboutCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, PrivionyxTheme.Metrics.tabBarClearance)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await loadAssistantAvailability()
            }
        }
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ForEach(AppearanceMode.allCases) { mode in
                    appearanceOption(mode)
                }
            }

            Text("Choose how Privionyx looks. System matches your device setting.")
                .font(.system(size: 12.5))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
        }
        .padding(14)
        .privionyxGlass(cornerRadius: 16)
    }

    private func appearanceOption(_ mode: AppearanceMode) -> some View {
        let isSelected = appearanceMode == mode

        return Button {
            appearanceMode = mode
        } label: {
            VStack(spacing: 7) {
                Image(systemName: mode.icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(mode.title)
                    .font(.system(size: 12, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(isSelected ? PrivionyxTheme.Colors.accent : PrivionyxTheme.Colors.secondaryInk)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? PrivionyxTheme.Colors.accentSoft : PrivionyxTheme.Colors.glassFillStrong)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Assistant

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(AssistantBackend.allCases.enumerated()), id: \.element.id) { index, backend in
                assistantOption(backend)

                if index < AssistantBackend.allCases.count - 1 {
                    GlassRowDivider()
                }
            }
        }
        .privionyxGlass(cornerRadius: 16)
    }

    private func assistantOption(_ backend: AssistantBackend) -> some View {
        let isSelected = assistantBackend == backend
        let availability = assistantAvailability[backend]

        return Button {
            assistantBackend = backend
        } label: {
            HStack(alignment: .top, spacing: 12) {
                GlassIconTile(systemImage: backend.icon, size: 30, isAccented: isSelected)

                VStack(alignment: .leading, spacing: 3) {
                    Text(backend.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)

                    Text(availability?.reason ?? backend.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(
                            availability?.reason == nil
                                ? PrivionyxTheme.Colors.secondaryInk
                                : PrivionyxTheme.Colors.warning
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? PrivionyxTheme.Colors.accent : PrivionyxTheme.Colors.tertiaryInk)
                    .padding(.top, 6)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func loadAssistantAvailability() async {
        for backend in AssistantBackend.allCases {
            assistantAvailability[backend] = await backend.makeAssistant().availability()
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        VStack(spacing: 0) {
            aboutRow(icon: "tray.full.fill", label: "Saved Receipts", value: "\(appState.receipts.count)")
            GlassRowDivider()
            aboutRow(icon: "dollarsign.circle.fill", label: "Currency", value: PrivionyxCurrencyFormatter.currentCurrencyCode)
            GlassRowDivider()
            aboutRow(icon: "info.circle.fill", label: "Version", value: appVersionText)
        }
        .privionyxGlass(cornerRadius: 16)
    }

    private func aboutRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            GlassIconTile(systemImage: icon, size: 30, isAccented: false)

            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PrivionyxTheme.Colors.ink)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
        }
        .padding(14)
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(PrivionyxAppState(container: .preview))
}

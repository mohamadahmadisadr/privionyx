import SwiftUI

struct SettingsView: View {
    @Environment(PrivionyxAppState.self) private var appState
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode: AppearanceMode = .system
    @AppStorage(AssistantBackend.storageKey) private var assistantBackend: AssistantBackend = .fallback
    @AppStorage(ReceiptExtractionConsent.storageKey) private var extractionConsent: ReceiptExtractionConsent = .useModelWhenAvailable
    @AppStorage(ReceiptExtractionConsent.downloadPromptSuppressedKey) private var downloadPromptSuppressed = false
    @State private var assistantAvailability: [AssistantBackend: AssistantAvailability] = [:]
    @State private var gemma = GemmaModelManager.shared
    @AppStorage(GemmaModelManager.allowsCellularDownloadKey) private var allowsCellularGemmaDownload = false
    @State private var isRemovingSamples = false
    @State private var isRemoveAdsPresented = false

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

                        GlassEyebrow("Receipt Scanning")
                        extractionCard

                        GlassEyebrow("Assistant")
                        assistantCard

                        BannerAdSlot(placement: .settings)

                        if appState.purchases.entitlement.removesAds == false, appState.bannerAds.isConfigured {
                            GlassEyebrow("Ads")
                            removeAdsCard
                        }

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
                gemma.refreshState()
                await loadAssistantAvailability()
            }
        }
    }

    // MARK: - Receipt scanning

    /// Where a "don't ask again" gets taken back.
    ///
    /// The prompt during a scan writes the same preference this reads, so a user who ticked
    /// the box has somewhere to go — without this, the checkbox would be a decision they
    /// could make once and never revisit.
    private var extractionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ReceiptExtractionConsent.allCases) { option in
                extractionOption(option)
            }

            if downloadPromptSuppressed, extractionConsent != .alwaysUseBuiltIn {
                Button("Re-enable the Gemma download prompt") {
                    downloadPromptSuppressed = false
                }
                .font(.system(size: 12.5, weight: .semibold))
                .padding(.top, 2)
            }
        }
        .padding(14)
        .privionyxGlass(cornerRadius: 18)
    }

    private func extractionOption(_ option: ReceiptExtractionConsent) -> some View {
        let isSelected = extractionConsent == option

        return Button {
            extractionConsent = option
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? PrivionyxTheme.Colors.accent : PrivionyxTheme.Colors.secondaryInk)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)

                    Text(option.detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
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
        // The Gemma row carries its own download control, so its detail line stays the
        // plain description rather than repeating a "download it in Settings" reason.
        let showReason = backend != .localGemma && availability?.reason != nil

        return VStack(spacing: 0) {
            Button {
                assistantBackend = backend
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    GlassIconTile(systemImage: backend.icon, size: 30, isAccented: isSelected)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(backend.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(PrivionyxTheme.Colors.ink)

                        Text(showReason ? (availability?.reason ?? backend.detail) : backend.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(showReason ? PrivionyxTheme.Colors.warning : PrivionyxTheme.Colors.secondaryInk)
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

            if backend == .localGemma {
                VStack(alignment: .leading, spacing: 10) {
                    gemmaDownloadControl
                    if gemmaShowsNetworkPreference {
                        gemmaCellularToggle
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
    }

    // MARK: - Gemma download

    @ViewBuilder
    private var gemmaDownloadControl: some View {
        switch gemma.state {
        case .unsupported:
            gemmaStatusRow(icon: "exclamationmark.triangle.fill", tint: PrivionyxTheme.Colors.tertiaryInk) {
                // Both figures, because the verdict was wrong once and nothing on screen
                // showed what was being compared.
                Text("Not supported on this device — Gemma needs \(gemmaMemoryFloorText) and this device reports \(GemmaModelCatalog.memoryDescription()).")
                    .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
            }

        case .notDownloaded:
            Button {
                gemma.download()
            } label: {
                gemmaActionLabel(icon: "arrow.down.circle.fill", text: "Download\(gemmaSizeSuffix)")
            }
            .buttonStyle(.plain)

        case let .downloading(progress):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress)
                    .tint(PrivionyxTheme.Colors.accent)
                HStack {
                    Text("Downloading… \(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    Spacer()
                    Button("Cancel") { gemma.cancel() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.danger)
                        .buttonStyle(.plain)
                }
            }

        case .ready:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(PrivionyxTheme.Colors.success)
                Text("Downloaded")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                Spacer()
                Button("Delete") { gemma.deleteModel() }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.danger)
                    .buttonStyle(.plain)
            }

        case let .failed(message):
            VStack(alignment: .leading, spacing: 8) {
                gemmaStatusRow(icon: "exclamationmark.triangle.fill", tint: PrivionyxTheme.Colors.warning) {
                    Text(message).foregroundStyle(PrivionyxTheme.Colors.warning)
                }
                Button {
                    gemma.download()
                } label: {
                    gemmaActionLabel(icon: "arrow.clockwise.circle.fill", text: "Retry")
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Only while there is a download left to do. Once the weights are on disk the preference
    /// governs nothing, and a toggle that changes nothing is worse than no toggle.
    private var gemmaShowsNetworkPreference: Bool {
        switch gemma.state {
        case .notDownloaded, .downloading, .failed: true
        case .ready, .unsupported: false
        }
    }

    private var gemmaCellularToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $allowsCellularGemmaDownload) {
                Text("Allow download over cellular")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
            }
            .tint(PrivionyxTheme.Colors.accent)

            // Named in gigabytes rather than described as "large", because the number is the
            // whole argument and most monthly allowances are smaller than it.
            Text(allowsCellularGemmaDownload
                 ? "\(gemmaSizeText) will be taken from your data plan. Low Data Mode is still respected."
                 : "Waits for Wi-Fi. \(gemmaSizeText) is more than many monthly data allowances.")
                .font(.system(size: 12))
                .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var gemmaSizeText: String {
        gemma.spec.map(GemmaModelCatalog.sizeDescription) ?? "The model"
    }

    private var gemmaMemoryFloorText: String {
        GemmaModelCatalog.lowestMemoryFloor.map(GemmaModelCatalog.memoryDescription) ?? "more memory"
    }

    private var gemmaSizeSuffix: String {
        gemma.spec.map { " (\(GemmaModelCatalog.sizeDescription(for: $0)))" } ?? ""
    }

    private func gemmaActionLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text).font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(PrivionyxTheme.Colors.onAccent)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(PrivionyxTheme.Colors.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func gemmaStatusRow<Content: View>(
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(tint)
            content()
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func loadAssistantAvailability() async {
        for backend in AssistantBackend.allCases {
            assistantAvailability[backend] = await backend.makeAssistant().availability()
        }
    }

    // MARK: - About

    /// Buying silence, and getting it back on a new device.
    ///
    /// Restore sits beside the purchase rather than behind it: guideline 3.1.1 requires a
    /// restore path for a non-consumable, and a user who reinstalls has no other way to stop
    /// paying twice for the same thing.
    private var removeAdsCard: some View {
        VStack(spacing: 0) {
            Button {
                isRemoveAdsPresented = true
            } label: {
                aboutRow(
                    icon: "nosign",
                    label: "Remove Ads",
                    value: appState.purchases.displayPrice ?? "",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)

            GlassRowDivider()

            Button {
                Task { await appState.purchases.restorePurchases() }
            } label: {
                aboutRow(
                    icon: "arrow.clockwise",
                    label: "Restore Purchases",
                    value: appState.purchases.isBusy ? "Checking…" : ""
                )
            }
            .buttonStyle(.plain)
            .disabled(appState.purchases.isBusy)
        }
        .privionyxGlass(cornerRadius: 16)
        .sheet(isPresented: $isRemoveAdsPresented) {
            RemoveAdsSheet()
        }
        .task { await appState.purchases.refresh() }
    }

    private var aboutCard: some View {
        VStack(spacing: 0) {
            aboutRow(icon: "tray.full.fill", label: "Saved Receipts", value: "\(appState.receipts.count)")
            GlassRowDivider()
            aboutRow(icon: "dollarsign.circle.fill", label: "Currency", value: PrivionyxCurrencyFormatter.currentCurrencyCode)
            GlassRowDivider()
            aboutRow(icon: "info.circle.fill", label: "Version", value: appVersionText)
            if appState.hasSampleReceipts {
                GlassRowDivider()
                Button {
                    Task { await removeSamples() }
                } label: {
                    sampleRemovalRow
                }
                .buttonStyle(.plain)
                .disabled(isRemovingSamples)
            }
            GlassRowDivider()
            NavigationLink {
                AcknowledgementsView()
            } label: {
                aboutRow(
                    icon: "text.document.fill",
                    label: "Acknowledgements",
                    value: "",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }
        .privionyxGlass(cornerRadius: 16)
    }

    private func aboutRow(
        icon: String,
        label: String,
        value: String,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            GlassIconTile(systemImage: icon, size: 30, isAccented: false)

            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PrivionyxTheme.Colors.ink)

            Spacer(minLength: 8)

            Text(value)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
            }
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    /// Present for as long as any sample remains, which is the whole reason it is here rather
    /// than only in the empty state: loading samples is what makes that empty state disappear.
    private var sampleRemovalRow: some View {
        HStack(spacing: 12) {
            GlassIconTile(systemImage: "sparkles.rectangle.stack.fill", size: 30, isAccented: false)

            VStack(alignment: .leading, spacing: 2) {
                Text(isRemovingSamples ? "Removing…" : "Remove Sample Receipts")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isRemovingSamples ? PrivionyxTheme.Colors.tertiaryInk : PrivionyxTheme.Colors.danger)
                Text("Deletes only receipts tagged \(PrivionyxSampleData.tag). Yours are untouched.")
                    .font(.system(size: 12))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
            }

            Spacer(minLength: 8)
        }
        .padding(14)
        .contentShape(Rectangle())
    }

    private func removeSamples() async {
        isRemovingSamples = true
        defer { isRemovingSamples = false }
        do {
            try await appState.removeSampleReceipts()
        } catch {
            appState.lastError = .deletingReceipt(error)
        }
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

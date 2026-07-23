import SwiftUI

struct DashboardView: View {
    let viewModel: DashboardViewModel
    @Environment(PrivionyxAppState.self) private var appState
    @Environment(AppCoordinator.self) private var coordinator
    @State private var selectedPeriod: DashboardPeriod = .monthly
    @State private var isShowingAllReceipts = false

    var body: some View {
        NavigationStack {
            ZStack {
                PrivionyxTheme.appBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        summaryCard
                        quickActions

                        if viewModel.receipts.isEmpty {
                            emptyState
                        } else {
                            insightsSection
                            budgetSection
                            categorySection
                            recentReceiptsSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, PrivionyxTheme.Metrics.tabBarClearance)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $isShowingAllReceipts) {
                ReceiptListView(appState: appState)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.greeting)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)

                Text("Expenses")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
            }

            Spacer()

            Button {
                coordinator.selectedTab = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(PrivionyxTheme.Colors.ink.opacity(0.75))
                    .frame(width: 40, height: 40)
                    .privionyxGlass(cornerRadius: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                GlassEyebrow(selectedPeriod.title)
                Spacer(minLength: 8)
                periodPicker
            }

            HStack(alignment: .bottom, spacing: 10) {
                Text(viewModel.totalSpent(for: selectedPeriod))
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let percentage = viewModel.comparisonPercentage(for: selectedPeriod) {
                    TrendChip(percentage: percentage)
                        .padding(.bottom, 6)
                }
            }
            .padding(.top, 6)

            // A series of all zeroes would draw a meaningless flat rule.
            let sparklineValues = viewModel.sparklineValues(for: selectedPeriod)
            if sparklineValues.contains(where: { $0 > 0 }) {
                Sparkline(values: sparklineValues)
                    .frame(height: 44)
                    .padding(.top, 14)
            }
        }
        .privionyxCardStyle()
    }

    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach(DashboardPeriod.allCases) { period in
                let isSelected = selectedPeriod == period

                Button {
                    withAnimation(.snappy(duration: 0.2)) { selectedPeriod = period }
                } label: {
                    Text(period.shortTitle)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isSelected ? PrivionyxTheme.Colors.accent : PrivionyxTheme.Colors.tertiaryInk)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background {
                            if isSelected {
                                Capsule().fill(PrivionyxTheme.Colors.accentSoft)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Quick actions

    private var quickActions: some View {
        HStack(spacing: 10) {
            quickAction(title: "Scan", icon: "camera.viewfinder", isAccented: true) {
                coordinator.selectedTab = .addReceipt
            }

            quickAction(title: "Ask AI", icon: "sparkles", isAccented: true) {
                coordinator.selectedTab = .assistant
            }

            quickAction(title: "Receipts", icon: "chart.bar.fill", isAccented: false) {
                isShowingAllReceipts = true
            }
        }
    }

    private func quickAction(title: String, icon: String, isAccented: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                GlassIconTile(systemImage: icon, isAccented: isAccented)
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .privionyxGlass(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sections

    @ViewBuilder
    private var insightsSection: some View {
        let insights = viewModel.insights()
        if insights.isEmpty == false {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionTitle("Insights")

                VStack(spacing: 10) {
                    ForEach(insights) { insight in
                        insightCard(insight)
                    }
                }
            }
        }
    }

    private func insightCard(_ insight: ExpenseInsight) -> some View {
        let tint = tint(for: insight.tone)

        return HStack(spacing: 12) {
            Image(systemName: insight.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(insight.detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .privionyxGlass(cornerRadius: 16)
    }

    private func tint(for tone: ExpenseInsight.Tone) -> Color {
        switch tone {
        case .alert:
            PrivionyxTheme.Colors.warning
        case .positive:
            PrivionyxTheme.Colors.success
        case .neutral:
            PrivionyxTheme.Colors.accent
        }
    }

    @ViewBuilder
    private var budgetSection: some View {
        let progress = viewModel.budgetProgress()
        if progress.isEmpty == false {
            VStack(alignment: .leading, spacing: 12) {
                GlassSectionTitle("Budgets")

                VStack(spacing: 15) {
                    ForEach(progress) { budgetBar($0) }
                }
                .privionyxCardStyle()
            }
        }
    }

    private func budgetBar(_ progress: BudgetProgress) -> some View {
        let tint: Color = progress.isOver
            ? PrivionyxTheme.Colors.danger
            : (progress.isNearLimit ? PrivionyxTheme.Colors.warning : PrivionyxTheme.Colors.accent)

        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text(progress.category)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)

                Spacer(minLength: 8)

                Text("\(PrivionyxCurrencyFormatter.string(for: progress.spent)) / \(PrivionyxCurrencyFormatter.string(for: progress.limit))")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(progress.isOver ? PrivionyxTheme.Colors.danger : PrivionyxTheme.Colors.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PrivionyxTheme.Colors.glassFillStrong)
                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, geometry.size.width * min(progress.fraction, 1)))
                }
            }
            .frame(height: 7)
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionTitle("Spending by Category")

            let shares = viewModel.categoryShares(for: selectedPeriod)

            if shares.isEmpty {
                Text("No spending recorded for \(selectedPeriod.title.lowercased()).")
                    .font(.system(size: 13))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
            } else {
                VStack(spacing: 12) {
                    ForEach(shares) { share in
                        CategoryShareBar(name: share.name, share: share.share, tint: share.color)
                    }
                }
            }
        }
    }

    private var recentReceiptsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionTitle("Recent Receipts", actionTitle: "See All") {
                isShowingAllReceipts = true
            }

            let recent = viewModel.recentReceipts()

            GlassRowGroup {
                ForEach(Array(recent.enumerated()), id: \.element.id) { index, receipt in
                    NavigationLink {
                        ReceiptDetailView(receipt: receipt)
                    } label: {
                        receiptRow(receipt, index: index)
                    }
                    .buttonStyle(.plain)

                    if index < recent.count - 1 {
                        GlassRowDivider()
                    }
                }
            }
        }
    }

    private func receiptRow(_ receipt: ReceiptItem, index: Int) -> some View {
        let isAccented = index.isMultiple(of: 2)

        return HStack(spacing: 12) {
            InitialTile(
                text: receipt.merchant,
                tint: isAccented ? PrivionyxTheme.Colors.accent : PrivionyxTheme.Colors.neutralTile,
                foreground: isAccented ? .white : PrivionyxTheme.Colors.ink
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(receipt.merchant)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(PrivionyxTheme.Colors.ink)
                    .lineLimit(1)

                Text("\(receipt.displayCategoryName) · \(Self.dateLabel(for: receipt.date))")
                    .font(.system(size: 12.5))
                    .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(PrivionyxCurrencyFormatter.string(for: receipt.amount))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(PrivionyxTheme.Colors.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// "Today" / "Yesterday" for the last two days, an abbreviated date otherwise.
    private static func dateLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSectionTitle("Start Here")

            GlassEmptyState(
                systemImage: "doc.text.viewfinder",
                title: "Save a receipt to unlock your spending overview",
                message: "Use the Camera tab to capture a paper receipt or import a photo. Totals, categories, and merchants appear here after review.",
                actionTitle: "Open Camera",
                action: { coordinator.selectedTab = .addReceipt }
            )
        }
    }
}

#Preview {
    DashboardView(viewModel: DashboardViewModel(receipts: []))
        .environment(PrivionyxAppState(container: .preview))
        .environment(AppCoordinator())
}

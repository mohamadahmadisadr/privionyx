import SwiftUI

struct PrivionyxRootView: View {
    @Environment(PrivionyxAppState.self) private var appState
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(viewModel: DashboardViewModel(appState: appState))
                .tabItem {
                    Label(AppTab.dashboard.title, systemImage: AppTab.dashboard.icon)
                }
                .tag(AppTab.dashboard)

            AddReceiptView(appState: appState)
                .tabItem {
                    Label(AppTab.addReceipt.title, systemImage: AppTab.addReceipt.icon)
                }
                .tag(AppTab.addReceipt)

            ReceiptListView(appState: appState)
                .tabItem {
                    Label(AppTab.receipts.title, systemImage: AppTab.receipts.icon)
                }
                .tag(AppTab.receipts)
        }
        .tint(PrivionyxTheme.Colors.accent)
        .toolbarBackground(PrivionyxTheme.Colors.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private enum AppTab: Hashable {
    case dashboard
    case addReceipt
    case receipts

    var title: String {
        switch self {
        case .dashboard:
            "Home"
        case .addReceipt:
            "Add"
        case .receipts:
            "Receipts"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:
            "rectangle.grid.2x2.fill"
        case .addReceipt:
            "plus.viewfinder"
        case .receipts:
            "list.bullet.rectangle.portrait.fill"
        }
    }
}

#Preview {
    PrivionyxRootView()
        .environment(PrivionyxAppState(container: .live(inMemory: true)))
}

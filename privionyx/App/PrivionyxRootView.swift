import SwiftUI

struct PrivionyxRootView: View {
    @Environment(PrivionyxAppState.self) private var appState
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator

        ZStack(alignment: .bottom) {
            // A real TabView keeps every screen alive across switches, so an in-progress
            // scan survives a trip to Home. Its own bar is hidden in favour of FloatingTabBar.
            // TabView does not forward a safe-area inset to its children, so each screen
            // reserves PrivionyxTheme.Metrics.tabBarClearance at its own bottom edge.
            TabView(selection: $coordinator.selectedTab) {
                DashboardView(viewModel: DashboardViewModel(receipts: appState.receipts))
                    .tag(AppTab.dashboard)
                    .toolbar(.hidden, for: .tabBar)

                AddReceiptView(appState: appState)
                    .tag(AppTab.addReceipt)
                    .toolbar(.hidden, for: .tabBar)

                AssistantView(appState: appState)
                    .tag(AppTab.assistant)
                    .toolbar(.hidden, for: .tabBar)

                SettingsView()
                    .tag(AppTab.settings)
                    .toolbar(.hidden, for: .tabBar)
            }

            FloatingTabBar(selection: $coordinator.selectedTab)
                .padding(.bottom, 6)
        }
    }
}

#Preview {
    PrivionyxRootView()
        .environment(PrivionyxAppState(container: .preview))
        .environment(AppCoordinator())
}

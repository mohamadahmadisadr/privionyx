import SwiftUI

struct PrivionyxRootView: View {
    @Environment(PrivionyxAppState.self) private var appState
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator

        // Native TabView: on iOS 26 this renders the system Liquid Glass tab bar and
        // manages its own safe-area inset, so screens don't reserve space for it.
        TabView(selection: $coordinator.selectedTab) {
            Tab(AppTab.dashboard.title, systemImage: AppTab.dashboard.icon, value: AppTab.dashboard) {
                DashboardView(viewModel: DashboardViewModel(receipts: appState.receipts))
            }

            Tab(AppTab.addReceipt.title, systemImage: AppTab.addReceipt.icon, value: AppTab.addReceipt) {
                AddReceiptView(appState: appState)
            }

            Tab(AppTab.assistant.title, systemImage: AppTab.assistant.icon, value: AppTab.assistant) {
                AssistantView(appState: appState)
            }

            Tab(AppTab.settings.title, systemImage: AppTab.settings.icon, value: AppTab.settings) {
                SettingsView()
            }
        }
    }
}

#Preview {
    PrivionyxRootView()
        .environment(PrivionyxAppState(container: .preview))
        .environment(AppCoordinator())
}

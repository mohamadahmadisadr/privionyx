import SwiftUI

struct PrivionyxRootView: View {
    @Environment(PrivionyxAppState.self) private var appState
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var coordinator = coordinator

        // Native TabView: on iOS 26 this renders the system Liquid Glass tab bar and
        // manages its own safe-area inset, so screens don't reserve space for it.
        TabView(selection: $coordinator.selectedTab) {
            // Banners live inside each screen's content, between its sections, rather than
            // being pinned here to the bottom of every tab.
            Tab(AppTab.dashboard.title, systemImage: AppTab.dashboard.icon, value: AppTab.dashboard) {
                DashboardView(viewModel: DashboardViewModel(receipts: appState.receipts))
            }

            // The capture tab deliberately has no banner. It is a camera viewfinder and a
            // review form the user is typing figures into; an ad under either is the kind of
            // thing that gets an app rejected, and it is the one screen where a mistap costs
            // the user a receipt.
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
        .environment(PrivionyxAppState.preview)
        .environment(AppCoordinator())
}

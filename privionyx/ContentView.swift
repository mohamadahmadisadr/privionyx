//
//  ContentView.swift
//  privionyx
//
//  Created by Mohammad Ahmadi on 2026-04-05.
//

import SwiftUI

struct ContentView: View {
    @Environment(PrivionyxAppState.self) private var appState
    @AppStorage(AppearanceMode.storageKey) private var appearanceMode: AppearanceMode = .system

    var body: some View {
        // Straight to the app. There is no loading screen in front of this on purpose: the
        // tab bar, the header and the quick actions do not depend on anything being read from
        // disk, so making the user watch a spinner before they can tap "Scan" bought nothing.
        // The screens underneath show placeholders for the parts still on their way.
        PrivionyxRootView()
            .task {
                await appState.initializeIfNeeded()
            }
            .preferredColorScheme(appearanceMode.colorScheme)
            // Titled by what failed rather than by the app's name, so the first line already
            // tells the user which of their actions didn't take effect.
            .alert(
                appState.lastError?.title ?? "Privionyx",
                isPresented: Binding<Bool>(
                    get: { appState.lastError != nil },
                    set: { newValue in
                        if newValue == false {
                            appState.lastError = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    appState.lastError = nil
                }
            } message: {
                Text(appState.lastError?.message ?? "")
            }
    }
}

#Preview {
    ContentView()
        .environment(PrivionyxAppState.preview)
        .environment(AppCoordinator())
}

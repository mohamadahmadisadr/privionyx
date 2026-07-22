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
        Group {
            if appState.isLaunching || appState.launchProgress < 1 {
                LaunchSplashView(
                    statusText: appState.launchStatusText
                )
            } else {
                PrivionyxRootView()
            }
        }
        .task {
            await appState.initializeIfNeeded()
        }
        .preferredColorScheme(appearanceMode.colorScheme)
            .alert(
                "Privionyx",
                isPresented: Binding<Bool>(
                    get: { appState.lastErrorMessage != nil },
                    set: { newValue in
                        if newValue == false {
                            appState.lastErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    appState.lastErrorMessage = nil
                }
            } message: {
                Text(appState.lastErrorMessage ?? "")
            }
    }
}

private struct LaunchSplashView: View {
    let statusText: String

    var body: some View {
        ZStack {
            PrivionyxTheme.appBackground
                .ignoresSafeArea()

            VStack(spacing: 18) {
                GlassIconTile(systemImage: "doc.text.viewfinder", size: 72)

                VStack(spacing: 6) {
                    Text("Privionyx")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)

                    Text("Turn receipts into clean expense records.")
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                }

                VStack(spacing: 8) {
                    ProgressView()

                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(PrivionyxTheme.Colors.tertiaryInk)
                }
            }
            .padding(30)
            .frame(maxWidth: 320)
            .privionyxCardStyle(cornerRadius: 28)
        }
    }
}

#Preview {
    ContentView()
        .environment(PrivionyxAppState(container: .preview))
        .environment(AppCoordinator())
}

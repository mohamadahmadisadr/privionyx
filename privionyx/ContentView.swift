//
//  ContentView.swift
//  privionyx
//
//  Created by Mohammad Ahmadi on 2026-04-05.
//

import SwiftUI

struct ContentView: View {
    @Environment(PrivionyxAppState.self) private var appState

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

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Privionyx")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)

                    Text("Private receipt intelligence, prepared on device.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(PrivionyxTheme.Colors.secondaryInk)
                }

                VStack(spacing: 14) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(PrivionyxTheme.Colors.accentStrong)

                    Text(statusText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(PrivionyxTheme.Colors.ink)
                        .multilineTextAlignment(.center)
                }
                .padding(18)
                .background(PrivionyxTheme.Colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(PrivionyxTheme.Colors.separator, lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    ContentView()
        .environment(PrivionyxAppState(container: .live(inMemory: true)))
}

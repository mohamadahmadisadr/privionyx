//
//  privionyxApp.swift
//  privionyx
//
//  Created by Mohammad Ahmadi on 2026-04-05.
//

import SwiftUI
import UIKit

/// Exists for the background download of the on-device model, which is the one thing the
/// app needs a UIKit lifecycle hook for: the system delivers its completion events to the
/// application delegate, and relaunches the app to do so if it isn't running.
@MainActor
final class PrivionyxAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Adopt a model download left running by a previous launch, so Settings shows real
        // progress instead of offering to start it over.
        GemmaModelManager.shared.reconnectToBackgroundSession()
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        GemmaModelManager.handleBackgroundSessionEvents(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }
}

@main
struct privionyxApp: App {
    @UIApplicationDelegateAdaptor(PrivionyxAppDelegate.self) private var appDelegate
    @State private var appState: PrivionyxAppState
    @State private var coordinator = AppCoordinator()

    init() {
        let container = PrivionyxAppContainer.live()
        _appState = State(initialValue: PrivionyxAppState(container: container))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(coordinator)
                .environment(\.managedObjectContext, appState.viewContext)
        }
    }
}

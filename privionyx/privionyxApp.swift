//
//  privionyxApp.swift
//  privionyx
//
//  Created by Mohammad Ahmadi on 2026-04-05.
//

import SwiftUI

@main
struct privionyxApp: App {
    @State private var appState: PrivionyxAppState

    init() {
        let container = PrivionyxAppContainer.live()
        _appState = State(initialValue: PrivionyxAppState(container: container))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(\.managedObjectContext, appState.viewContext)
        }
    }
}

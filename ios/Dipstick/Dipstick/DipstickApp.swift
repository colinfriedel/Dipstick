//
//  DipstickApp.swift
//  Dipstick
//

import SwiftUI

@main
struct DipstickApp: App {
    /// When the backend URL changes we key the whole view tree off it, so every
    /// screen (and its view model, and its repository) is rebuilt against the
    /// new server.
    @AppStorage(AppEnvironment.backendOverrideKey) private var backendOverride = ""

    var body: some Scene {
        WindowGroup {
            VehicleListView()
                .id(backendOverride)
        }
    }
}

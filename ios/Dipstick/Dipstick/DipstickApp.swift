//
//  DipstickApp.swift
//  Dipstick
//

import SwiftUI

@main
struct DipstickApp: App {
    /// Any change to a backend URL bumps these, which changes the root view's
    /// id, which rebuilds the whole tree (and every view model + repository)
    /// against the new servers — no relaunch needed.
    @AppStorage(AppEnvironment.vehicleOverrideKey) private var vehicleOverride = ""
    @AppStorage(AppEnvironment.activityOverrideKey) private var activityOverride = ""

    var body: some Scene {
        WindowGroup {
            VehicleListView()
                .id("\(vehicleOverride)|\(activityOverride)")
        }
    }
}

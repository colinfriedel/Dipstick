//
//  DipstickApp.swift
//  Dipstick
//
//  Created by Colin Friedel on 10/12/26.
//

import SwiftUI
import SwiftData

@main
struct DipstickApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Vehicle.self,
            FuelEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            VehicleListView()
        }
        .modelContainer(sharedModelContainer)
    }
}

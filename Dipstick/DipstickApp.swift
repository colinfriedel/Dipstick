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
    @State private var tripRecorder = TripRecorder()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Vehicle.self,
            FuelEntry.self,
            MaintenanceEntry.self,
            PartUsed.self,
            Trip.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            #if DEBUG
            SampleData.seedIfRequested(into: container.mainContext)
            #endif
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            VehicleListView()
                .environment(tripRecorder)
        }
        .modelContainer(sharedModelContainer)
    }
}

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
    /// Shared with the Start/Stop Trip Shortcuts actions, which can run with
    /// no window open.
    static let modelContainer: ModelContainer = {
        let schema = Schema([
            Vehicle.self,
            FuelEntry.self,
            MaintenanceEntry.self,
            PartUsed.self,
            Trip.self,
            ScheduleItem.self,
            TestEntry.self,
            TestReading.self,
            ReferencePage.self,
            ReferencePhoto.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            ServiceNotesMove.run(in: container.mainContext)
            #if DEBUG
            SampleData.seedIfRequested(into: container.mainContext)
            // Acts like the Control Center button, for testing in the simulator.
            if ProcessInfo.processInfo.arguments.contains("-requestFillUp") {
                QuickActions.shared.fillUpRequested = Date()
            }
            #endif
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            VehicleListView()
                .environment(TripRecorder.shared)
                // Supports large accessibility sizes; the two very largest
                // make number readouts unusable on a phone screen.
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
        .modelContainer(Self.modelContainer)
        .onChange(of: scenePhase) {
            // Swiping the app away (or iOS closing it) can skip autosave.
            if scenePhase != .active { Self.modelContainer.mainContext.saveNow() }
            // Back up whenever the app is put away with changes.
            if scenePhase == .background { BackupManager.shared.backUp(context: Self.modelContainer.mainContext) }
            // See whether earlier backups made it to iCloud.
            if scenePhase == .active { Task { await BackupManager.shared.checkUploads() } }
        }
    }
}

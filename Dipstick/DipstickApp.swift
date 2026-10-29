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
        // In the app group (shared with the widgets), where SwiftData already
        // put it once the group was added. iCloud sync is Dipstick's own
        // (see Sync/), so SwiftData's built-in sync stays off even once the
        // app has iCloud.
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .identifier(CarDirectory.appGroup),
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            ServiceNotesMove.run(in: container.mainContext)
            SyncIDs.assign(in: container.mainContext)
            #if DEBUG
            SampleData.seedIfRequested(into: container.mainContext)
            // Acts like the Control Center button, for testing in the simulator.
            if ProcessInfo.processInfo.arguments.contains("-requestFillUp") {
                QuickActions.shared.fillUpRequested = Date()
            }
            // Acts like a per-car button: -requestFillUpFor "Car name".
            let arguments = ProcessInfo.processInfo.arguments
            if let i = arguments.firstIndex(of: "-requestFillUpFor"), i + 1 < arguments.count,
               let car = ((try? container.mainContext.fetch(FetchDescriptor<Vehicle>())) ?? [])
                .first(where: { $0.name == arguments[i + 1] }) {
                QuickActions.shared.fillUpCarID = car.directoryID
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
                // Lock Screen widget: dipstick://fillup?car=ID.
                .onOpenURL { url in
                    guard let carID = CarDirectory.carID(inFillUpURL: url) else { return }
                    QuickActions.shared.fillUpCarID = carID
                    QuickActions.shared.fillUpRequested = Date()
                }
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

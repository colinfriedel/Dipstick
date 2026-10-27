//
//  TripIntents.swift
//  Dipstick
//

import AppIntents
import SwiftData

/// "Start Trip" action for Shortcuts. Meant for a personal automation like
/// "When CarPlay connects" or "When Peggy connects", so a drive is recorded
/// without opening the app. Picks the car from the current connection; an
/// unknown connection is recorded as an unreviewed trip.
struct StartTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Trip"
    static let description = IntentDescription(
        "Starts recording a drive for the car you're connected to (CarPlay or Bluetooth)."
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let recorder = TripRecorder.shared
        guard !recorder.isRecording else {
            return .result(dialog: "Already recording a trip.")
        }
        let context = DipstickApp.modelContainer.mainContext
        let connection = CarConnection.current()
        let vehicle = Vehicle.matching(connection, in: context)
        recorder.start(for: vehicle, automatic: true)

        guard recorder.isRecording else {
            return .result(dialog: "Couldn't start: Dipstick needs location access set to Always.")
        }
        let car = vehicle?.name ?? (connection == nil ? "no car connected" : "an unrecognized car")
        return .result(dialog: "Recording a trip for \(car).")
    }
}

/// "Stop Trip" action for Shortcuts, e.g. "When CarPlay disconnects". It
/// doesn't stop immediately: CarPlay head units can drop out and reconnect
/// mid-drive, so the trip ends once you've been parked for a few minutes, and
/// the request is cancelled if the car reconnects first.
struct StopTripIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Trip"
    static let description = IntentDescription(
        "Ends the drive being recorded once you're parked. Reconnecting to the car first keeps the trip going."
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let recorder = TripRecorder.shared
        guard recorder.isRecording else {
            return .result(dialog: "No trip was being recorded.")
        }
        recorder.requestStopWhenParked()
        return .result(dialog: "The trip will end once you're parked.")
    }
}

/// Makes the actions show up in the Shortcuts app without any setup.
struct DipstickShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogFillUpIntent(),
            phrases: ["Log a fill-up in \(.applicationName)", "Log a \(.applicationName) fill-up"],
            shortTitle: "Log Fill-Up",
            systemImageName: "fuelpump.fill"
        )
        AppShortcut(
            intent: StartTripIntent(),
            phrases: ["Start a \(.applicationName) trip"],
            shortTitle: "Start Trip",
            systemImageName: "location.fill"
        )
        AppShortcut(
            intent: StopTripIntent(),
            phrases: ["Stop the \(.applicationName) trip"],
            shortTitle: "Stop Trip",
            systemImageName: "stop.circle"
        )
    }
}

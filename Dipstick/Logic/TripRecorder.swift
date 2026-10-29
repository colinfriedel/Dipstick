//
//  TripRecorder.swift
//  Dipstick
//

import Foundation
import CoreLocation
import AVFoundation
import Observation
import SwiftData

/// The car audio output the phone is connected to (CarPlay or Bluetooth).
struct CarConnection: Equatable {
    /// "CarPlay (CarPlay)" or "Peggy (Bluetooth)". Every CarPlay car reports
    /// the same name, so this is for display only.
    let name: String
    /// Stable per car: the hardware address at the start of the audio route's
    /// uid (e.g. "1C:50:1E:B4:BC:F1"). Used to recognize which car it is.
    let id: String

    /// "1C:50:1E:B4:BC:F1-Audio-AudioMain-1592…" → "1C:50:1E:B4:BC:F1".
    static func stableID(fromUID uid: String) -> String {
        uid.split(separator: "-", maxSplits: 1).first.map(String.init) ?? uid
    }

    static func current() -> CarConnection? {
        let carPorts: Set<AVAudioSession.Port> = [.carAudio, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
        guard let port = AVAudioSession.sharedInstance().currentRoute.outputs
            .first(where: { carPorts.contains($0.portType) }) else { return nil }
        let kind = port.portType == .carAudio ? "CarPlay" : "Bluetooth"
        return CarConnection(name: "\(port.portName) (\(kind))", id: stableID(fromUID: port.uid))
    }
}

/// Records one drive at a time: collects GPS samples (kept in memory only),
/// shows a live city/highway split, and saves a `Trip` summary when stopped.
///
/// One shared instance (`shared`) is used by the UI and by the Start/Stop Trip
/// Shortcuts actions, so a trip started by a CarPlay automation with the app
/// closed is the same one the app shows when opened.
@Observable
@MainActor
final class TripRecorder {
    /// On first use, saves any trip left behind by an interrupted recording
    /// (see `TripCheckpoint`).
    static let shared: TripRecorder = {
        let recorder = TripRecorder()
        if let checkpoint = TripCheckpoint.read() {
            checkpoint.recover(into: DipstickApp.modelContainer.mainContext)
        }
        return recorder
    }()

    /// Rules for ending a trip that was started automatically.
    enum AutoStop {
        /// At or above this speed you're driving (faster than walking away from
        /// the car).
        static let movingMPH = 10.0
        /// Not moving this long, with the car connection gone or Stop Trip
        /// requested, ends the trip. Long enough for a red light.
        static let parkedSeconds: TimeInterval = 180
        /// Before the car has driven at all (warming up, connections still
        /// settling), wait this long instead, so the trip isn't ended before
        /// the drive starts.
        static let notYetDrivenSeconds: TimeInterval = 600

        /// True once the trip should end. Losing the connection alone never
        /// ends a trip (head units reboot mid-drive); you also have to stop
        /// moving. `lastMoving` is the trip start until it has driven.
        static func shouldStop(
            now: Date,
            lastMoving: Date,
            hasDriven: Bool = true,
            connectionPresent: Bool,
            stopRequested: Bool
        ) -> Bool {
            guard !connectionPresent || stopRequested else { return false }
            let wait = hasDriven ? parkedSeconds : notYetDrivenSeconds
            return now.timeIntervalSince(lastMoving) >= wait
        }
    }

    private(set) var vehicle: Vehicle?
    private(set) var startDate: Date?
    private(set) var split = TripClassifier.Split()
    /// Latest speed in mph, nil before the first fix.
    private(set) var currentMPH: Double?
    private(set) var connection: CarConnection?
    private(set) var authorizationDenied = false
    private(set) var authorizationStatus: CLAuthorizationStatus

    var isRecording: Bool { startDate != nil }
    var connectionName: String? { connection?.name }

    private var samples: [TripClassifier.Sample] = []
    /// Last time the car was going at least `AutoStop.movingMPH` (two
    /// readings in a row, so one noisy GPS fix while walking doesn't count).
    private(set) var lastMoving = Date()
    /// Whether the trip has reached driving speed yet.
    private(set) var hasDriven = false
    private var fastReadingsInARow = 0
    /// Stop Trip ran (e.g. "CarPlay disconnects"); end once parked.
    private(set) var stopRequested = false
    /// The trip's car connection is currently missing (checked every 15 s).
    private(set) var connectionLost = false
    private var isAutomatic = false
    private var lastCheckpoint = Date.distantPast

    /// The car seems to be off: an automatic trip whose connection is gone or
    /// whose Stop Trip ran. Slow movement (walking away) isn't counted then,
    /// and the trip ends once parked for `AutoStop.parkedSeconds`.
    var isEnding: Bool { isAutomatic && (stopRequested || connectionLost) }

    /// When an ending trip will save if you stay parked.
    var endsAt: Date? {
        guard isEnding else { return nil }
        return lastMoving + (hasDriven ? AutoStop.parkedSeconds : AutoStop.notYetDrivenSeconds)
    }
    private var updatesTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var backgroundSession: CLBackgroundActivitySession?
    private let locationManager = CLLocationManager()

    init() {
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: Permission

    /// Recording that starts with the app closed (from a Shortcuts automation)
    /// needs "Always" location access.
    var canRecordInBackground: Bool { authorizationStatus == .authorizedAlways }

    func requestAlwaysAuthorization() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else {
            locationManager.requestAlwaysAuthorization()
        }
        Task {
            // The result isn't reported synchronously; re-read shortly after.
            try? await Task.sleep(for: .seconds(1))
            refreshAuthorization()
        }
    }

    func refreshAuthorization() {
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: Recording

    /// Starts a trip. `vehicle` may be nil (unknown car): the trip is still
    /// recorded and saved as unreviewed. `automatic` trips stop on their own
    /// once their car connection has been gone for a while.
    func start(for vehicle: Vehicle?, automatic: Bool = false) {
        guard !isRecording else { return }
        refreshAuthorization()
        switch authorizationStatus {
        case .denied, .restricted:
            authorizationDenied = true
            return
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            break
        }
        authorizationDenied = false

        self.vehicle = vehicle
        startDate = Date()
        samples = []
        split = .init()
        currentMPH = nil
        connection = CarConnection.current()

        // Keeps location updates flowing while the screen is locked or the app
        // is in the background.
        backgroundSession = CLBackgroundActivitySession()
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.automotiveNavigation) {
                    guard let self, !Task.isCancelled else { return }
                    if let location = update.location {
                        self.add(location)
                    }
                }
            } catch {
                // The stream ends on cancellation; nothing to recover.
            }
        }
        lastMoving = Date()
        hasDriven = false
        fastReadingsInARow = 0
        stopRequested = false
        connectionLost = false
        isAutomatic = automatic
        if automatic {
            startAutoStopWatchdog()
        }
    }

    /// Asks an automatic trip to end once you're parked, instead of right
    /// away, so a head unit reboot mid-drive doesn't split the trip. Cancelled
    /// if the car connection comes back first.
    func requestStopWhenParked() {
        guard isRecording else { return }
        stopRequested = true
        isAutomatic = true
        if watchdogTask == nil { startAutoStopWatchdog() }
    }

    /// Stops recording and saves the trip (unless it was too short to matter).
    /// `trimAfter` drops samples after that time (walking away from the car).
    @discardableResult
    func stop(into context: ModelContext, trimAfter: Date? = nil) -> Trip? {
        guard let startDate else { return nil }
        stopUpdates()
        if let trimAfter {
            samples.removeAll { $0.timestamp > trimAfter }
        }

        let final = TripClassifier.classify(samples)
        #if DEBUG
        SpeedLog.save(samples, tripStart: startDate)
        #endif
        defer {
            self.startDate = nil
            self.vehicle = nil
            samples = []
            currentMPH = nil
            isAutomatic = false
            stopRequested = false
            connectionLost = false
        }
        guard final.totalMiles >= 0.1 else { return nil }

        // Never save to a car deleted since the drive began.
        let car = vehicle.flatMap { $0.modelContext == nil || $0.isDeleted ? nil : $0 }
        return Trip.save(
            start: startDate, end: trimAfter ?? Date(), split: final,
            vehicle: car, connection: connection, in: context
        )
    }

    /// A car is about to be deleted: a drive recording for it carries on as
    /// a drive to sort, instead of saving to the deleted car.
    func forget(_ vehicle: Vehicle) {
        guard self.vehicle?.persistentModelID == vehicle.persistentModelID else { return }
        self.vehicle = nil
    }

    func discard() {
        stopUpdates()
        isAutomatic = false
        stopRequested = false
        connectionLost = false
        startDate = nil
        vehicle = nil
        samples = []
        currentMPH = nil
    }

    private func writeCheckpoint() {
        guard let startDate else { return }
        lastCheckpoint = Date()
        TripCheckpoint(
            startDate: startDate,
            vehicleID: vehicle?.persistentModelID,
            connectionName: connection?.name,
            connectionID: connection?.id,
            // Not driving yet counts as "moving" so a short checkpoint isn't
            // trimmed to nothing.
            lastMoving: isEnding ? lastMoving : Date(),
            samples: samples
        ).write()
    }

    private func stopUpdates() {
        TripCheckpoint.delete()
        lastCheckpoint = .distantPast
        updatesTask?.cancel()
        updatesTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
    }

    /// Checks every 15 s whether an automatic trip should end (see
    /// `AutoStop.shouldStop`). A returning car connection cancels a pending
    /// Stop Trip request, and may fill in the car if the trip started without one.
    private func startAutoStopWatchdog() {
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, self.isRecording else { return }
                let context = DipstickApp.modelContainer.mainContext
                let current = CarConnection.current()
                // An unrecognized trip picks up its car as soon as any of that
                // car's connections appears (e.g. Bluetooth first, CarPlay later).
                if self.vehicle == nil, let match = Vehicle.matching(current, in: context) {
                    self.vehicle = match
                }
                if self.connection == nil { self.connection = current }
                // Still "in the car" if connected to the trip's connection or to
                // any connection of the trip's car.
                let present = current != nil
                    && (current?.id == self.connection?.id || self.vehicle?.knowsConnection(current?.id) == true)
                self.connectionLost = !present
                if present { self.stopRequested = false }
                if AutoStop.shouldStop(now: Date(), lastMoving: self.lastMoving, hasDriven: self.hasDriven,
                                       connectionPresent: present, stopRequested: self.stopRequested) {
                    self.stop(into: DipstickApp.modelContainer.mainContext, trimAfter: self.lastMoving)
                    return
                }
            }
        }
    }

    private func add(_ location: CLLocation) {
        let sample = TripClassifier.Sample(location)
        let mph = sample.speed >= 0 ? sample.speed * TripClassifier.mphPerMetersPerSecond : nil
        if let mph {
            currentMPH = mph
            let accurate = sample.horizontalAccuracy >= 0
                && sample.horizontalAccuracy <= TripClassifier.maxHorizontalAccuracyMeters
            fastReadingsInARow = (mph >= AutoStop.movingMPH && accurate) ? fastReadingsInARow + 1 : 0
            if fastReadingsInARow >= 2 {
                lastMoving = sample.timestamp
                hasDriven = true
            }
        }
        // With the car off, only count driving speeds: walking away from the
        // car or shuffling around a parking lot isn't the car's mileage.
        if isEnding, (mph ?? 0) < AutoStop.movingMPH {
            return
        }
        samples.append(sample)
        if sample.timestamp.timeIntervalSince(lastCheckpoint) >= TripCheckpoint.interval {
            writeCheckpoint()
        }
        // Re-classifying the whole drive is cheap (a few thousand samples) and
        // keeps the live numbers identical to what will be saved.
        if samples.count % 5 == 0 {
            split = TripClassifier.classify(samples)
        }
        if connection == nil {
            connection = CarConnection.current()
        }
    }

    #if DEBUG
    /// Debug-only: every current audio output with its type and unique ID.
    static func audioRouteDetails() -> [String] {
        AVAudioSession.sharedInstance().currentRoute.outputs.map {
            "\($0.portName) · \($0.portType.rawValue)\nID: \($0.uid)"
        }
    }
    #endif
}

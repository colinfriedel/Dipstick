//
//  TripRecorder.swift
//  Dipstick
//

import Foundation
import CoreLocation
import AVFoundation
import Observation
import SwiftData

/// Records one drive at a time: collects GPS samples (kept in memory only),
/// shows a live city/highway split, and saves a `Trip` summary when stopped.
/// One shared instance lives in the environment so recording continues while
/// you move around the app or lock the screen.
@Observable
@MainActor
final class TripRecorder {
    private(set) var vehicle: Vehicle?
    private(set) var startDate: Date?
    private(set) var split = TripClassifier.Split()
    /// Latest speed in mph, nil before the first fix.
    private(set) var currentMPH: Double?
    private(set) var connectionName: String?
    private(set) var authorizationDenied = false

    var isRecording: Bool { startDate != nil }

    private var samples: [TripClassifier.Sample] = []
    private var updatesTask: Task<Void, Never>?
    private var backgroundSession: CLBackgroundActivitySession?
    private let locationManager = CLLocationManager()

    func start(for vehicle: Vehicle) {
        guard !isRecording else { return }
        switch locationManager.authorizationStatus {
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
        connectionName = Self.carConnectionName()

        // Keeps location updates flowing while the screen is locked.
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
    }

    /// Stops recording and saves the trip (unless it was too short to matter).
    @discardableResult
    func stop(into context: ModelContext) -> Trip? {
        guard let startDate else { return nil }
        updatesTask?.cancel()
        updatesTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil

        let final = TripClassifier.classify(samples)
        defer {
            self.startDate = nil
            self.vehicle = nil
            samples = []
            currentMPH = nil
        }
        guard final.totalMiles >= 0.1 else { return nil }

        let trip = Trip(
            startDate: startDate, endDate: Date(),
            cityMiles: final.cityMiles, highwayMiles: final.highwayMiles,
            status: vehicle == nil ? .unreviewed : .assigned,
            connectionName: connectionName
        )
        context.insert(trip)
        trip.vehicle = vehicle
        return trip
    }

    func discard() {
        updatesTask?.cancel()
        updatesTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        startDate = nil
        vehicle = nil
        samples = []
        currentMPH = nil
    }

    private func add(_ location: CLLocation) {
        let sample = TripClassifier.Sample(location)
        samples.append(sample)
        if sample.speed >= 0 {
            currentMPH = sample.speed * TripClassifier.mphPerMetersPerSecond
        }
        // Re-classifying the whole drive is cheap (a few thousand samples) and
        // keeps the live numbers identical to what will be saved.
        if samples.count % 5 == 0 {
            split = TripClassifier.classify(samples)
        }
        if connectionName == nil {
            connectionName = Self.carConnectionName()
        }
    }

    /// The name of the car audio output (CarPlay or Bluetooth), if connected.
    static func carConnectionName() -> String? {
        let carPorts: Set<AVAudioSession.Port> = [.carAudio, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
        return AVAudioSession.sharedInstance().currentRoute.outputs
            .first { carPorts.contains($0.portType) }
            .map { "\($0.portName) (\(label(for: $0.portType)))" }
    }

    #if DEBUG
    /// Debug-only: every current audio output with its type and unique ID, to
    /// see whether two CarPlay cars can be told apart (both report "CarPlay").
    static func audioRouteDetails() -> [String] {
        AVAudioSession.sharedInstance().currentRoute.outputs.map {
            "\($0.portName) · \($0.portType.rawValue)\nID: \($0.uid)"
        }
    }
    #endif

    private static func label(for port: AVAudioSession.Port) -> String {
        switch port {
        case .carAudio: "CarPlay"
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: "Bluetooth"
        default: port.rawValue
        }
    }
}

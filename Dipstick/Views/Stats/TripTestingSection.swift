//
//  TripTestingSection.swift
//  Dipstick
//

#if DEBUG
import SwiftUI
import SwiftData

/// Debug-only: start a trip recording and list recorded trips, for checking
/// the city/highway classifier on real drives. Not shown in Release builds.
struct TripTestingSection: View {
    let vehicle: Vehicle

    @Environment(TripRecorder.self) private var recorder
    @Environment(\.modelContext) private var modelContext
    @State private var isShowingRecorder = false

    private var trips: [Trip] {
        (vehicle.trips ?? []).sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        Section {
            Button(recorder.isRecording ? "Show Recording" : "Start Trip", systemImage: "location.fill") {
                if !recorder.isRecording { recorder.start(for: vehicle) }
                isShowingRecorder = true
            }
            .disabled(recorder.isRecording && recorder.vehicle?.persistentModelID != vehicle.persistentModelID)

            if recorder.authorizationDenied {
                Text("Location access is off. Turn it on in Settings > Privacy & Security > Location Services > Dipstick.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            ForEach(trips) { trip in
                TripRow(trip: trip)
                    .swipeActions {
                        Button("Delete", role: .destructive) { modelContext.delete(trip) }
                    }
                    .contextMenu {
                        if let log = SpeedLog.existingURL(forTripStartingAt: trip.startDate) {
                            ShareLink(item: log) {
                                Label("Export Speed Log", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
            }
        } header: {
            Text("Trips (testing)")
        } footer: {
            Text("Debug builds only. Record a drive to check the city/highway split. Long-press a trip to export its speed log (speeds only, no locations).")
        }
        .fullScreenCover(isPresented: $isShowingRecorder) {
            TripRecordingView()
        }

        AutomaticTripsSection(vehicle: vehicle)
    }
}

/// Debug-only setup for automatic trips: Always location access and which
/// CarPlay/Bluetooth connection belongs to this car.
private struct AutomaticTripsSection: View {
    let vehicle: Vehicle

    @Environment(TripRecorder.self) private var recorder
    @Environment(\.scenePhase) private var scenePhase
    @State private var message: String?

    var body: some View {
        Section {
            LabeledContent("Location access") {
                Text(recorder.canRecordInBackground ? "Always" : statusText)
                    .foregroundStyle(recorder.canRecordInBackground ? Color.secondary : Color.orange)
            }
            if !recorder.canRecordInBackground {
                Button("Allow Always Access", systemImage: "location.circle") {
                    recorder.requestAlwaysAuthorization()
                }
                Text("If no prompt appears, open Settings > Privacy & Security > Location Services > Dipstick and choose Always.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(vehicle.connections, id: \.id) { connection in
                HStack {
                    VStack(alignment: .leading) {
                        Text(connection.name)
                        Text(connection.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Remove", systemImage: "minus.circle.fill", role: .destructive) {
                        vehicle.removeConnection(id: connection.id)
                        message = nil
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }
            if vehicle.connections.isEmpty {
                Text("No connections yet").foregroundStyle(.secondary)
            }
            Button("Add Current Connection", systemImage: "link") {
                if let connection = CarConnection.current() {
                    if vehicle.knowsConnection(connection.id) {
                        message = "\(connection.name) is already linked."
                    } else {
                        vehicle.addConnection(connection)
                        message = "Linked \(connection.name)."
                    }
                } else {
                    message = "Not connected to CarPlay or Bluetooth right now."
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Automatic trips (testing)")
        } footer: {
            Text("Connect to this car, then tap Add Current Connection. A car can have several (e.g. Bluetooth and CarPlay). Trips on any of them are assigned to \(vehicle.name) automatically.")
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active { recorder.refreshAuthorization() }
        }
    }

    private var statusText: String {
        switch recorder.authorizationStatus {
        case .authorizedWhenInUse: "While Using"
        case .denied: "Off"
        case .restricted: "Restricted"
        case .notDetermined: "Not asked yet"
        default: "Unknown"
        }
    }
}

/// Home screen, Debug only: trips that started on an unknown connection (or
/// none). Assigning one also teaches the app that connection, so future trips
/// on it are assigned automatically.
struct UnassignedTripsSection: View {
    @Query(filter: #Predicate<Trip> { $0.vehicle == nil }, sort: \Trip.startDate, order: .reverse)
    private var trips: [Trip]
    @Query(sort: \Vehicle.name) private var vehicles: [Vehicle]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if !trips.isEmpty {
            Section {
                ForEach(trips) { trip in
                    HStack {
                        TripRow(trip: trip)
                        Spacer()
                        Menu {
                            ForEach(vehicles) { vehicle in
                                Button(vehicle.name) { assign(trip, to: vehicle) }
                            }
                            Divider()
                            Button("Not My Car (Delete)", role: .destructive) {
                                modelContext.delete(trip)
                            }
                        } label: {
                            Image(systemName: "car.badge.gearshape")
                                .font(.title3)
                        }
                        .accessibilityLabel("Assign trip")
                    }
                }
            } header: {
                Text("Unassigned trips (testing)")
            } footer: {
                Text("Pick the car to assign a trip. Its connection is remembered, so the next trip in that car is assigned automatically.")
            }
        }
    }

    private func assign(_ trip: Trip, to vehicle: Vehicle) {
        trip.vehicle = vehicle
        trip.status = .assigned
        if let id = trip.connectionID {
            vehicle.addConnection(CarConnection(name: trip.connectionName ?? id, id: id))
        }
    }
}

private struct TripRow: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(trip.startDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.headline)
                Spacer()
                Text(trip.totalMiles, format: .number.precision(.fractionLength(1)))
                    .font(.headline) + Text(" mi").font(.headline)
            }
            if let fraction = trip.highwayFraction {
                Text("\(fraction, format: .percent.precision(.fractionLength(0))) highway · \(trip.cityMiles, format: .number.precision(.fractionLength(1))) city mi · \(trip.highwayMiles, format: .number.precision(.fractionLength(1))) hwy mi")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(trip.connectionName ?? "No car connection")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Full-screen live view while recording: speed, miles, split, car connection.
struct TripRecordingView: View {
    @Environment(TripRecorder.self) private var recorder
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @ViewBuilder
    private func endingStatus(at now: Date) -> some View {
        if let mph = recorder.currentMPH, mph >= TripRecorder.AutoStop.movingMPH {
            Label("Car disconnected · still driving, recording", systemImage: "car.fill")
        } else if let endsAt = recorder.endsAt {
            let remaining = max(0, endsAt.timeIntervalSince(now))
            Label(
                remaining > 0
                    ? "Parked · saving in \(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))"
                    : "Parked · saving now…",
                systemImage: "parkingsign.circle"
            )
            .monospacedDigit()
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if recorder.isEnding {
                    Section {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            endingStatus(at: context.date)
                        }
                    } footer: {
                        Text("The car connection is gone or Stop Trip ran. Driving speeds keep the trip going (in case the head unit just rebooted); otherwise it saves after \(Int(TripRecorder.AutoStop.parkedSeconds / 60)) minutes parked. Walking isn't counted.")
                    }
                }

                Section {
                    LabeledContent("Speed") {
                        Text(recorder.currentMPH.map { "\(Int($0.rounded())) mph" } ?? "Waiting for GPS…")
                            .monospacedDigit()
                    }
                    LabeledContent("Miles", value: recorder.split.totalMiles.formatted(.number.precision(.fractionLength(2))))
                    LabeledContent("City", value: recorder.split.cityMiles.formatted(.number.precision(.fractionLength(2))))
                    LabeledContent("Highway", value: recorder.split.highwayMiles.formatted(.number.precision(.fractionLength(2))))
                    if recorder.split.totalMiles > 0 {
                        LabeledContent("Highway %", value: (recorder.split.highwayMiles / recorder.split.totalMiles)
                            .formatted(.percent.precision(.fractionLength(0))))
                    }
                } header: {
                    Text(recorder.vehicle?.name ?? "Trip")
                } footer: {
                    Text("Miles are counted in half-mile stretches, so the totals update in steps. Recording continues with the screen locked.")
                }

                Section("Car connection") {
                    Text(recorder.connectionName ?? "None detected")
                }

                Section {
                    TimelineView(.periodic(from: .now, by: 2)) { _ in
                        let outputs = TripRecorder.audioRouteDetails()
                        if outputs.isEmpty {
                            Text("No audio output").foregroundStyle(.secondary)
                        }
                        ForEach(outputs, id: \.self) { output in
                            Text(output)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("Audio route details")
                } footer: {
                    Text("Compare the ID in each CarPlay car. Long-press to copy.")
                }
            }
            .navigationTitle("Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hide") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Discard", role: .destructive) {
                        recorder.discard()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Stop & Save") {
                        recorder.stop(into: modelContext)
                        dismiss()
                    }
                }
            }
        }
    }
}
#endif

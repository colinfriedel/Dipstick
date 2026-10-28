//
//  TripsViews.swift
//  Dipstick
//

import SwiftUI
import SwiftData

// MARK: - Stats tab: recent drives

/// DRIVES on the Stats tab: the latest recorded drives for this car, a
/// button to record one by hand, and a link to all of them. Drives feed the
/// city and highway MPG above.
struct DrivesPanel: View {
    let vehicle: Vehicle
    let onShowAll: () -> Void
    let onRecord: () -> Void

    @Environment(TripRecorder.self) private var recorder

    var body: some View {
        let trips = vehicle.sortedTrips
        VStack(spacing: 0) {
            ForEach(Array(trips.prefix(3).enumerated()), id: \.element.id) { index, trip in
                if index > 0 { FormDivider() }
                TripRow(trip: trip)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            if trips.isEmpty {
                Text("No drives recorded yet. Set up automatic trips in Shortcuts, or record one here.")
                    .font(.dipstick(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            FormDivider()
            HStack(spacing: 0) {
                Button(action: onRecord) {
                    Label(recordingThisCar ? "Show recording" : "Record a drive",
                          systemImage: recordingThisCar ? "record.circle" : "location.fill")
                        .font(.dipstick(14, .semibold, relativeTo: .body))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(recorder.isRecording && !recordingThisCar)
                if trips.count > 3 {
                    Rectangle().fill(Theme.divider).frame(width: 1, height: 28)
                    Button(action: onShowAll) {
                        Text("All \(trips.count)")
                            .font(.dipstick(14, .semibold, relativeTo: .body))
                            .foregroundStyle(Theme.accentText)
                            .frame(minWidth: 90, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .panel(radius: Theme.Radius.field)
    }

    private var recordingThisCar: Bool {
        recorder.isRecording && recorder.vehicle?.persistentModelID == vehicle.persistentModelID
    }
}

extension Vehicle {
    /// This car's recorded drives, newest first.
    var sortedTrips: [Trip] {
        (trips ?? []).filter { $0.status == .assigned }.sorted { $0.startDate > $1.startDate }
    }
}

/// One drive: when, how far, and its city/highway split.
struct TripRow: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(trip.startDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    .font(.dipstick(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("\(trip.totalMiles.formatted(.number.precision(.fractionLength(1)))) mi")
                    .font(.readout(15, relativeTo: .body))
                    .foregroundStyle(Theme.text)
            }
            if let fraction = trip.highwayFraction {
                SplitBar(highwayFraction: fraction)
                Text("\(trip.cityMiles.formatted(.number.precision(.fractionLength(1)))) city · \(trip.highwayMiles.formatted(.number.precision(.fractionLength(1)))) highway · \(fraction.formatted(.percent.precision(.fractionLength(0)))) highway")
                    .font(.dipstick(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// City (gray) and highway (accent) shares of a drive.
struct SplitBar: View {
    let highwayFraction: Double

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Rectangle().fill(Theme.faint)
                Rectangle().fill(Theme.accent).frame(width: proxy.size.width * highwayFraction)
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - All drives

/// Every recorded drive for a car, newest first. Swipe to delete one (a
/// drive in someone else's car, or a test).
struct TripsListView: View {
    let vehicle: Vehicle
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let trips = vehicle.sortedTrips
        List {
            HStack(spacing: 14) {
                Button("Done") { dismiss() }
                    .buttonStyle(SmallControlButtonStyle())
                vehicle.chip
                Text("DRIVES")
                    .font(.dipstick(15, .semibold, relativeTo: .headline))
                    .tracking(2)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .plainRow(top: 8, bottom: 10)

            let miles = trips.reduce(0) { $0 + $1.totalMiles }
            let highway = trips.reduce(0) { $0 + $1.highwayMiles }
            Text("\(trips.count) drive\(trips.count == 1 ? "" : "s") · \(miles.formatted(.number.precision(.fractionLength(0)))) mi\(miles > 0 ? " · \((highway / miles).formatted(.percent.precision(.fractionLength(0)))) highway" : "")")
                .font(.dipstick(13, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
                .plainRow(top: 0, bottom: 8)

            ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                TripRow(trip: trip)
                    .panelRow(.of(index, count: trips.count))
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            modelContext.delete(trip)
                            modelContext.saveNow()
                        }
                        .tint(Theme.red)
                    }
                    #if DEBUG
                    .contextMenu {
                        if let log = SpeedLog.existingURL(forTripStartingAt: trip.startDate) {
                            ShareLink(item: log) {
                                Label("Export Speed Log", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                    #endif
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
    }
}

// MARK: - Home: drives from an unknown car

/// Home: a row for drives recorded on a connection the app doesn't know yet.
struct UnassignedTripsRow: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "car.badge.gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count) drive\(count == 1 ? "" : "s") to sort")
                        .font(.dipstick(15, .semibold, relativeTo: .body))
                        .foregroundStyle(Theme.text)
                    Text("Recorded in a car Dipstick doesn't know yet")
                        .font(.dipstick(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .panel(radius: Theme.Radius.field)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}

/// Drives that started on an unknown connection (or none). Picking the car
/// also teaches the app that connection, so later drives in it are assigned
/// automatically. "Not my car" removes the drive.
struct UnassignedTripsView: View {
    @Query(filter: #Predicate<Trip> { $0.vehicle == nil }, sort: \Trip.startDate, order: .reverse)
    private var trips: [Trip]
    @Query(sort: \Vehicle.name) private var vehicles: [Vehicle]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Button("Done") { dismiss() }
                        .buttonStyle(SmallControlButtonStyle())
                    Text("DRIVES TO SORT")
                        .font(.dipstick(15, .semibold, relativeTo: .headline))
                        .tracking(2)
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                .padding(.bottom, 6)

                Text("Pick the car for each drive. Dipstick remembers that car's connection, so its next drives are sorted automatically.")
                    .font(.dipstick(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if trips.isEmpty {
                    Text("All sorted.")
                        .font(.dipstick(15, relativeTo: .body))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 20)
                }
                ForEach(trips) { trip in
                    VStack(alignment: .leading, spacing: 10) {
                        TripRow(trip: trip)
                        Text(trip.connectionName.map { "Connected to \($0)" } ?? "No car connection")
                            .font(.dipstick(12, relativeTo: .caption))
                            .foregroundStyle(Theme.muted)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(vehicles) { vehicle in
                                    Button { assign(trip, to: vehicle) } label: {
                                        HStack(spacing: 6) {
                                            vehicle.chip
                                            Text(vehicle.name)
                                        }
                                    }
                                    .buttonStyle(ChipStyle())
                                }
                                Button("Not my car", role: .destructive) {
                                    modelContext.delete(trip)
                                    modelContext.saveNow()
                                }
                                .buttonStyle(ChipStyle(foreground: Theme.red))
                            }
                            .padding(.vertical, 1)
                        }
                        .scrollClipDisabled()
                    }
                    .padding(14)
                    .panel(radius: Theme.Radius.field)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
    }

    private func assign(_ trip: Trip, to vehicle: Vehicle) {
        trip.vehicle = vehicle
        trip.status = .assigned
        if let id = trip.connectionID {
            vehicle.addConnection(CarConnection(name: trip.connectionName ?? id, id: id))
        }
        modelContext.saveNow()
    }
}

/// A capsule chip button (car names on the sort screen).
private struct ChipStyle: ButtonStyle {
    var foreground: Color = Theme.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dipstick(14, .semibold, relativeTo: .body))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(minHeight: 40)
            .background(Capsule().fill(configuration.isPressed ? Theme.selectedFill : Theme.controlSmallFill))
            .overlay(Capsule().strokeBorder(Theme.controlSmallBorder, lineWidth: 1))
    }
}

// MARK: - Recording

/// Full-screen view while a drive is recording: speed, miles so far and the
/// city/highway split, with Stop & Save and Discard. Recording carries on
/// with the screen locked or this closed.
struct TripRecordingView: View {
    @Environment(TripRecorder.self) private var recorder
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDiscard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Button("Hide") { dismiss() }
                        .buttonStyle(SmallControlButtonStyle())
                    if let vehicle = recorder.vehicle { vehicle.chip }
                    Text((recorder.vehicle?.name ?? "Drive").uppercased())
                        .font(.dipstick(15, .semibold, relativeTo: .headline))
                        .tracking(2)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                .padding(.bottom, 4)

                if recorder.authorizationDenied {
                    StatusLine(status: .overdue,
                               text: "Location access is off. Turn it on in Settings › Privacy & Security › Location Services › Dipstick.")
                }

                if recorder.isEnding {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        endingStatus(at: context.date)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel(radius: Theme.Radius.field)
                }

                TileRow {
                    ReadoutTile("Speed") {
                        Text(recorder.currentMPH.map { "\(Int($0.rounded()))" } ?? "--")
                            .font(.readout(30, relativeTo: .largeTitle))
                            .foregroundStyle(Theme.text)
                            .monospacedDigit()
                        + Text(" mph").font(.dipstick(13, relativeTo: .caption)).foregroundStyle(Theme.muted)
                    }
                    ReadoutTile("Miles", highlighted: true) {
                        Text(recorder.split.totalMiles.formatted(.number.precision(.fractionLength(1))))
                            .font(.readout(30, relativeTo: .largeTitle))
                            .foregroundStyle(Theme.accent)
                            .monospacedDigit()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    let split = recorder.split
                    HStack {
                        SmallCapsLabel("City \(split.cityMiles.formatted(.number.precision(.fractionLength(1)))) mi")
                        Spacer()
                        SmallCapsLabel("Highway \(split.highwayMiles.formatted(.number.precision(.fractionLength(1)))) mi")
                    }
                    SplitBar(highwayFraction: split.totalMiles > 0 ? split.highwayMiles / split.totalMiles : 0)
                        .opacity(split.totalMiles > 0 ? 1 : 0.35)
                    Text(recorder.currentMPH == nil
                         ? "Waiting for GPS…"
                         : "Miles count in half-mile stretches, so they update in steps.")
                        .font(.dipstick(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
                .padding(14)
                .panel(radius: Theme.Radius.field)

                FormRow("Car connection") {
                    Text(recorder.connectionName ?? "None")
                        .font(.dipstick(14, relativeTo: .body))
                        .foregroundStyle(Theme.text)
                }
                .padding(.vertical, 2)
                .panel(radius: Theme.Radius.field)

                Text("Keeps recording with the screen locked or this screen closed. Only city and highway miles are saved, never your route.")
                    .font(.dipstick(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)

                #if DEBUG
                audioRouteDetails
                #endif
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button("Discard") { isConfirmingDiscard = true }
                    .buttonStyle(SmallControlButtonStyle(foreground: Theme.red))
                    .frame(height: 60)
                Button("Stop & save") {
                    recorder.stop(into: modelContext)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(Theme.ground)
        }
        .confirmationDialog("Discard this drive?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
            Button("Discard Drive", role: .destructive) {
                recorder.discard()
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func endingStatus(at now: Date) -> some View {
        if let mph = recorder.currentMPH, mph >= TripRecorder.AutoStop.movingMPH {
            StatusLine(status: .ok, text: "Car disconnected · still driving, so still recording")
        } else if let endsAt = recorder.endsAt {
            let remaining = max(0, endsAt.timeIntervalSince(now))
            StatusLine(status: .dueSoon,
                       text: remaining > 0
                       ? "Parked · saving in \(Duration.seconds(remaining).formatted(.time(pattern: .minuteSecond)))"
                       : "Parked · saving now…")
                .monospacedDigit()
        }
    }

    #if DEBUG
    private var audioRouteDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            SmallCapsLabel("Audio route (debug)")
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                let outputs = TripRecorder.audioRouteDetails()
                VStack(alignment: .leading, spacing: 4) {
                    if outputs.isEmpty { Text("No audio output") }
                    ForEach(outputs, id: \.self) { Text($0).textSelection(.enabled) }
                }
                .font(.readout(11, relativeTo: .caption2))
                .foregroundStyle(Theme.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Theme.panelBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }
    #endif
}

// MARK: - Location access

/// Shown on the Stats tab until Dipstick has "Always" location access, which
/// automatic trips need (they start with the app closed).
struct LocationAccessNotice: View {
    @Environment(TripRecorder.self) private var recorder
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if !recorder.canRecordInBackground {
                VStack(alignment: .leading, spacing: 8) {
                    StatusLine(status: .dueSoon, text: "Automatic trips need location set to Always")
                    Text(recorder.authorizationStatus == .notDetermined
                         ? "Drives started by a Shortcuts automation run with Dipstick closed, so location access has to be Always. Only city and highway miles are saved, never your route."
                         : "Open Settings › Dipstick › Location and choose Always. Only city and highway miles are saved, never your route.")
                        .font(.dipstick(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(recorder.authorizationStatus == .notDetermined || recorder.authorizationStatus == .authorizedWhenInUse
                           && !triedAlways ? "Allow location" : "Open Settings") {
                        if recorder.authorizationStatus == .notDetermined
                            || (recorder.authorizationStatus == .authorizedWhenInUse && !triedAlways) {
                            triedAlways = recorder.authorizationStatus == .authorizedWhenInUse
                            recorder.requestAlwaysAuthorization()
                        } else if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .font(.dipstick(14, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.accentText)
                    .buttonStyle(.borderless)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panel(radius: Theme.Radius.field, border: Theme.amber.opacity(0.6))
            }
        }
        .onChange(of: scenePhase) { if scenePhase == .active { recorder.refreshAuthorization() } }
    }

    /// iOS only shows the "Change to Always" prompt once; after that it's Settings.
    @AppStorage("trips.askedForAlways") private var triedAlways = false
}

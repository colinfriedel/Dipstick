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
            }
        } header: {
            Text("Trips (testing)")
        } footer: {
            Text("Debug builds only. Record a drive to check the city/highway split.")
        }
        .fullScreenCover(isPresented: $isShowingRecorder) {
            TripRecordingView()
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

    var body: some View {
        NavigationStack {
            List {
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

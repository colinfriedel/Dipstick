//
//  OdometerUpdateView.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Sheet to record a new odometer reading without logging fuel or
/// service, e.g. for a car that's driven but rarely filled up. Only moves the
/// reading forward; lowering it (to fix a typo) is done in Edit Vehicle.
struct OdometerUpdateView: View {
    let vehicle: Vehicle

    @Environment(\.dismiss) private var dismiss
    @State private var reading: String
    @FocusState private var isFocused: Bool

    init(vehicle: Vehicle) {
        self.vehicle = vehicle
        _reading = State(initialValue: String(vehicle.currentOdometer))
    }

    private var parsed: Int? { Units.parseWholeNumber(reading) }

    private var canSave: Bool {
        parsed.map { $0 > vehicle.currentOdometer } ?? false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Odometer") {
                        TextField("Miles", text: $reading)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($isFocused)
                    }
                } footer: {
                    if let parsed, parsed < vehicle.currentOdometer {
                        Text("Lower than the current \(Units.miles(vehicle.currentOdometer)). To fix a wrong reading, use Edit.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Current: \(Units.miles(vehicle.currentOdometer)). Mileage-based due dates update right away.")
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Update Odometer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let parsed { vehicle.recordOdometer(parsed) }
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .task { await focusAfterPresentation { isFocused = true } }
        }
    }
}

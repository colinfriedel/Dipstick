//
//  VehicleFormView.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Sheet for adding a new vehicle (pass `nil`) or editing an existing one.
struct VehicleFormView: View {
    let vehicle: Vehicle?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var year: String
    @State private var make: String
    @State private var model: String
    @State private var vin: String
    @State private var odometer: String

    init(vehicle: Vehicle? = nil) {
        self.vehicle = vehicle
        _name = State(initialValue: vehicle?.name ?? "")
        _year = State(initialValue: vehicle?.year.map(String.init) ?? "")
        _make = State(initialValue: vehicle?.make ?? "")
        _model = State(initialValue: vehicle?.model ?? "")
        _vin = State(initialValue: vehicle?.vin ?? "")
        _odometer = State(initialValue: vehicle.map { String($0.currentOdometer) } ?? "")
    }

    private var isEditing: Bool { vehicle != nil }

    // MARK: Parsed values

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var parsedOdometer: Int? {
        let digits = odometer.filter { $0 != "," && !$0.isWhitespace }
        guard let value = Int(digits), value >= 0 else { return nil }
        return value
    }

    private var parsedYear: Int? { Int(year.trimmingCharacters(in: .whitespaces)) }

    private static let validYears = 1900...(Calendar.current.component(.year, from: Date()) + 2)

    private var yearIsValid: Bool {
        year.trimmingCharacters(in: .whitespaces).isEmpty
            || parsedYear.map(Self.validYears.contains) == true
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && parsedOdometer != nil && yearIsValid
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nickname (e.g. Daily Driver)", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    TextField("Year", text: $year)
                        .keyboardType(.numberPad)
                    TextField("Make", text: $make)
                        .textInputAutocapitalization(.words)
                    TextField("Model", text: $model)
                        .textInputAutocapitalization(.words)
                    TextField("VIN (optional)", text: $vin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } header: {
                    Text("Car")
                } footer: {
                    if !yearIsValid {
                        Text("Enter a year between \(String(Self.validYears.lowerBound)) and \(String(Self.validYears.upperBound)).")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    TextField("Current odometer", text: $odometer)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Odometer (miles)")
                } footer: {
                    if !isEditing {
                        Text("Not sure of the exact reading? A close guess is fine. You can change it later.")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Vehicle" : "New Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: Saving

    private func save() {
        guard let odometerValue = parsedOdometer else { return }
        let target = vehicle ?? Vehicle(name: trimmedName)

        target.name = trimmedName
        target.year = parsedYear
        target.make = nilIfBlank(make)
        target.model = nilIfBlank(model)
        target.vin = nilIfBlank(vin)?.uppercased()
        target.currentOdometer = odometerValue

        if vehicle == nil {
            modelContext.insert(target)
        }
        dismiss()
    }

    private func nilIfBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview("Add") {
    VehicleFormView()
        .modelContainer(for: Vehicle.self, inMemory: true)
}

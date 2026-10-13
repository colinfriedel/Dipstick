//
//  FuelEntryFormView.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Sheet for logging a fill-up (pass no entry) or editing one. Kept short so
/// logging at the pump takes well under 30 seconds.
struct FuelEntryFormView: View {
    let vehicle: Vehicle
    let entry: FuelEntry?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var odometer: String
    @State private var gallons: String
    @State private var totalCost: String
    @State private var isFullTank: Bool
    @State private var station: String
    @State private var notes: String

    private enum Field { case odometer, gallons, totalCost }
    @FocusState private var focusedField: Field?

    init(vehicle: Vehicle, entry: FuelEntry? = nil) {
        self.vehicle = vehicle
        self.entry = entry
        _date = State(initialValue: entry?.date ?? Date())
        _odometer = State(initialValue: String(entry?.odometer ?? vehicle.currentOdometer))
        _gallons = State(initialValue: entry.map {
            $0.gallons.formatted(.number.precision(.fractionLength(0...3)).grouping(.never))
        } ?? "")
        _totalCost = State(initialValue: entry.flatMap { $0.isCostKnown ? String(format: "%.2f", $0.totalCost) : nil } ?? "")
        _isFullTank = State(initialValue: entry?.isFullTank ?? true)
        _station = State(initialValue: entry?.station ?? "")
        _notes = State(initialValue: entry?.notes ?? "")
    }

    private var isEditing: Bool { entry != nil }

    // MARK: Parsed values and validation

    private var parsedOdometer: Int? {
        Units.parseWholeNumber(odometer).flatMap { $0 >= 0 ? $0 : nil }
    }

    private var parsedGallons: Double? {
        Units.parseDecimal(gallons).flatMap { $0 > 0 ? $0 : nil }
    }

    /// Blank = cost unknown (stored as 0). nil = not a valid amount.
    private var parsedTotalCost: Double? {
        if totalCost.trimmingCharacters(in: .whitespaces).isEmpty { return 0 }
        return Units.parseDecimal(totalCost).flatMap { $0 >= 0 ? $0 : nil }
    }

    /// This vehicle's other fill-ups (excluding the one being edited).
    private var otherEntries: [FuelEntry] {
        (vehicle.fuelEntries ?? []).filter { $0.persistentModelID != entry?.persistentModelID }
    }

    private var duplicateEntry: FuelEntry? {
        guard let reading = parsedOdometer else { return nil }
        return otherEntries.first { $0.odometer == reading }
    }

    /// The highest-odometer fill-up above this reading, if any. Lower readings are
    /// allowed (e.g. backfilling old receipts) but worth pointing out.
    private var higherEntry: FuelEntry? {
        guard let reading = parsedOdometer else { return nil }
        return otherEntries.filter { $0.odometer > reading }.max { $0.odometer < $1.odometer }
    }

    private var canSave: Bool {
        parsedOdometer != nil && parsedGallons != nil && parsedTotalCost != nil && duplicateEntry == nil
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    LabeledContent("Odometer") {
                        TextField("Miles", text: $odometer)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .odometer)
                    }
                } footer: {
                    odometerMessage
                }

                Section {
                    LabeledContent("Gallons") {
                        TextField("0.000", text: $gallons)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .gallons)
                    }
                    LabeledContent("Total cost") {
                        TextField("$0.00", text: $totalCost)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .totalCost)
                    }
                    if let gallons = parsedGallons, let cost = parsedTotalCost, cost > 0 {
                        LabeledContent("Price", value: Units.pricePerGallon(cost / gallons))
                    }
                    Toggle("Filled the tank", isOn: $isFullTank)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if totalCost.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("Don't know the cost? Leave it blank; spend stats will skip this fill-up.")
                        }
                        if !isFullTank {
                            Text("Partial fills aren't given their own MPG. Their gallons count toward the next full tank.")
                        }
                    }
                }

                Section("Optional") {
                    TextField("Station", text: $station)
                        .textInputAutocapitalization(.words)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
            }
            .keyboardDoneButton()
            .navigationTitle(isEditing ? "Edit Fill-Up" : "Log Fill-Up")
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
            .task {
                if !isEditing { await focusAfterPresentation { focusedField = .odometer } }
            }
        }
    }

    @ViewBuilder
    private var odometerMessage: some View {
        if let duplicate = duplicateEntry {
            Text("You already logged a fill-up at \(Units.miles(duplicate.odometer)) on \(duplicate.date.formatted(date: .abbreviated, time: .omitted)).")
                .foregroundStyle(.red)
        } else if let higher = higherEntry {
            Text("Lower than your \(higher.date.formatted(date: .abbreviated, time: .omitted)) fill-up at \(Units.miles(higher.odometer)). That's fine if you're logging an older receipt.")
                .foregroundStyle(.orange)
        } else if !isEditing {
            Text("Last reading: \(Units.miles(vehicle.currentOdometer)).")
        }
    }

    // MARK: Saving

    private func save() {
        guard let odometerValue = parsedOdometer,
              let gallonsValue = parsedGallons,
              let costValue = parsedTotalCost else { return }

        let target = entry ?? FuelEntry(odometer: odometerValue, gallons: gallonsValue, totalCost: costValue)
        target.date = date
        target.odometer = odometerValue
        target.gallons = gallonsValue
        target.totalCost = costValue
        target.isFullTank = isFullTank
        target.station = nilIfBlank(station)
        target.notes = nilIfBlank(notes)

        if entry == nil {
            modelContext.insert(target)
            target.vehicle = vehicle
        }
        vehicle.recordOdometer(odometerValue)
        dismiss()
    }

    private func nilIfBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Vehicle.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let vehicle = Vehicle(name: "Daily Driver", currentOdometer: 48_210)
    container.mainContext.insert(vehicle)
    return FuelEntryFormView(vehicle: vehicle)
        .modelContainer(container)
}

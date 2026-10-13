//
//  MaintenanceEntryFormView.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Sheet for logging a service (pass no entry) or editing one. Works for DIY
/// jobs (cost adds up the parts) and shop visits (type the bill's total).
struct MaintenanceEntryFormView: View {
    let vehicle: Vehicle
    let entry: MaintenanceEntry?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Every logged service, so custom service names show up as options.
    @Query private var allEntries: [MaintenanceEntry]

    @State private var serviceChoice: String
    @State private var customService: String
    @State private var date: Date
    @State private var odometer: String
    @State private var parts: [PartDraft]
    /// A total typed by hand; nil means "use the parts total".
    @State private var manualCost: String?
    @State private var everyMiles: String
    @State private var everyMonths: String
    @State private var lastPrefill = MaintenanceSchedule.Interval()
    @State private var notes: String

    private static let otherChoice = "Other…"

    struct PartDraft: Identifiable {
        let id = UUID()
        var name: String
        var cost: String
    }

    init(vehicle: Vehicle, entry: MaintenanceEntry? = nil) {
        self.vehicle = vehicle
        self.entry = entry

        _serviceChoice = State(initialValue: entry?.serviceType ?? ServiceType.builtIn[0])
        _customService = State(initialValue: "")
        _date = State(initialValue: entry?.date ?? Date())
        _odometer = State(initialValue: String(entry?.odometer ?? vehicle.currentOdometer))
        _notes = State(initialValue: entry?.notes ?? "")

        let existingParts = entry?.sortedParts ?? []
        _parts = State(initialValue: existingParts.map {
            PartDraft(name: $0.name, cost: $0.cost > 0 ? Self.money($0.cost) : "")
        })
        let partsSum = existingParts.reduce(0) { $0 + $1.cost }
        if let entry, abs(entry.cost - partsSum) > 0.005 {
            _manualCost = State(initialValue: Self.money(entry.cost))
        } else {
            _manualCost = State(initialValue: nil)
        }

        let interval = entry.map {
            MaintenanceSchedule.interval(odometer: $0.odometer, date: $0.date, due: $0.due)
        } ?? .init()
        _everyMiles = State(initialValue: interval.miles.map(String.init) ?? "")
        _everyMonths = State(initialValue: interval.months.map(String.init) ?? "")
    }

    private var isEditing: Bool { entry != nil }

    // MARK: Service type

    private var serviceOptions: [String] {
        ServiceType.options(addingUsed: allEntries.map(\.serviceType)) + [Self.otherChoice]
    }

    private var resolvedServiceType: String {
        serviceChoice == Self.otherChoice
            ? customService.trimmingCharacters(in: .whitespacesAndNewlines)
            : serviceChoice
    }

    // MARK: Cost

    private var partsTotal: Double {
        parts.reduce(0) { $0 + (Units.parseDecimal($1.cost) ?? 0) }
    }

    private var costText: Binding<String> {
        Binding(
            get: { manualCost ?? (partsTotal > 0 ? Self.money(partsTotal) : "") },
            set: { manualCost = $0.isEmpty ? nil : $0 }
        )
    }

    private var parsedCost: Double? {
        guard let manualCost else { return partsTotal }
        return Units.parseDecimal(manualCost).flatMap { $0 >= 0 ? $0 : nil }
    }

    // MARK: Validation

    private var parsedOdometer: Int? {
        Units.parseWholeNumber(odometer).flatMap { $0 >= 0 ? $0 : nil }
    }

    /// nil = invalid; .some(nil) = left blank.
    private func optionalPositiveInt(_ text: String) -> Int?? {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return .some(nil) }
        return Units.parseWholeNumber(text).flatMap { $0 > 0 ? .some($0) : nil }
    }

    private var interval: MaintenanceSchedule.Interval? {
        guard let miles = optionalPositiveInt(everyMiles),
              let months = optionalPositiveInt(everyMonths) else { return nil }
        return .init(miles: miles, months: months)
    }

    private var partsAreValid: Bool {
        parts.allSatisfy { $0.cost.isEmpty || (Units.parseDecimal($0.cost).map { $0 >= 0 } ?? false) }
    }

    private var canSave: Bool {
        !resolvedServiceType.isEmpty && parsedOdometer != nil && parsedCost != nil
            && interval != nil && partsAreValid
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Service", selection: $serviceChoice) {
                        ForEach(serviceOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                    if serviceChoice == Self.otherChoice {
                        TextField("Service name", text: $customService)
                            .textInputAutocapitalization(.sentences)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    LabeledContent("Odometer") {
                        TextField("Miles", text: $odometer)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    odometerMessage
                }

                Section("Parts") {
                    ForEach($parts) { $part in
                        HStack {
                            TextField("Part name", text: $part.name)
                            TextField("$0.00", text: $part.cost)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                        }
                    }
                    .onDelete { parts.remove(atOffsets: $0) }
                    Button("Add Part", systemImage: "plus") {
                        parts.append(PartDraft(name: "", cost: ""))
                    }
                }

                Section {
                    LabeledContent("Total cost") {
                        TextField("$0.00", text: costText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    costMessage
                }

                Section {
                    LabeledContent("Every") {
                        HStack {
                            TextField("5000", text: $everyMiles)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            Text("mi").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Or every") {
                        HStack {
                            TextField("6", text: $everyMonths)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            Text("months").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Next due (optional)")
                } footer: {
                    dueMessage
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
            }
            .keyboardDoneButton()
            .navigationTitle(isEditing ? "Edit Service" : "Log Service")
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
            .onAppear { if !isEditing { prefillInterval() } }
            .onChange(of: serviceChoice) { if !isEditing { prefillInterval() } }
        }
    }

    // MARK: Footers

    @ViewBuilder
    private var odometerMessage: some View {
        if let reading = parsedOdometer, reading < vehicle.currentOdometer, !isEditing {
            Text("Lower than the current \(Units.miles(vehicle.currentOdometer)). That's fine for older records.")
        } else if !isEditing {
            Text("Current odometer: \(Units.miles(vehicle.currentOdometer)).")
        }
    }

    @ViewBuilder
    private var costMessage: some View {
        if manualCost != nil, partsTotal > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text("Parts add up to \(Units.currency(partsTotal)); the rest counts as labor or fees.")
                Button("Use parts total") { manualCost = nil }
                    .font(.footnote)
            }
        } else if partsTotal > 0 {
            Text("Adds up your parts. Type a different total to include labor or shop fees.")
        } else {
            Text("For a shop visit, enter the total from the bill.")
        }
    }

    @ViewBuilder
    private var dueMessage: some View {
        if let interval, let reading = parsedOdometer,
           let summary = MaintenanceSchedule.nextDue(odometer: reading, date: date, every: interval).summary {
            Text("Due at \(summary)\(interval.miles != nil && interval.months != nil ? ", whichever comes first" : "").")
        } else if interval == nil {
            Text("Enter whole numbers for the interval.")
                .foregroundStyle(.red)
        }
    }

    // MARK: Interval prefill

    /// Offer the interval used last time for this service on this vehicle,
    /// without overwriting anything the user typed.
    private func prefillInterval() {
        let current = MaintenanceSchedule.Interval(
            miles: Units.parseWholeNumber(everyMiles),
            months: Units.parseWholeNumber(everyMonths)
        )
        guard current.isEmpty || current == lastPrefill else { return }

        let previous = (vehicle.maintenanceEntries ?? [])
            .filter { $0.serviceType.caseInsensitiveCompare(resolvedServiceType) == .orderedSame }
            .max { $0.date < $1.date }
        let suggestion = previous.map {
            MaintenanceSchedule.interval(odometer: $0.odometer, date: $0.date, due: $0.due)
        } ?? .init()

        everyMiles = suggestion.miles.map(String.init) ?? ""
        everyMonths = suggestion.months.map(String.init) ?? ""
        lastPrefill = suggestion
    }

    // MARK: Saving

    private func save() {
        guard let odometerValue = parsedOdometer,
              let costValue = parsedCost,
              let interval else { return }

        let target = entry ?? MaintenanceEntry(odometer: odometerValue, serviceType: resolvedServiceType)
        let due = MaintenanceSchedule.nextDue(odometer: odometerValue, date: date, every: interval)

        target.date = date
        target.odometer = odometerValue
        target.serviceType = resolvedServiceType
        target.cost = costValue
        target.notes = nilIfBlank(notes)
        target.nextDueOdometer = due.odometer
        target.nextDueDate = due.date

        if entry == nil {
            modelContext.insert(target)
            target.vehicle = vehicle
        }

        // Replace the parts wholesale; simpler than diffing a short list.
        for old in target.parts ?? [] {
            modelContext.delete(old)
        }
        for draft in parts {
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let cost = Units.parseDecimal(draft.cost) ?? 0
            guard !name.isEmpty || cost > 0 else { continue }
            let part = PartUsed(name: name.isEmpty ? "Part" : name, cost: cost)
            modelContext.insert(part)
            part.entry = target
        }

        vehicle.recordOdometer(odometerValue)
        dismiss()
    }

    private func nilIfBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func money(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Vehicle.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let vehicle = Vehicle(name: "Project Car", currentOdometer: 131_870)
    container.mainContext.insert(vehicle)
    return MaintenanceEntryFormView(vehicle: vehicle)
        .modelContainer(container)
}

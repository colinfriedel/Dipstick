//
//  VehicleDetailView.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// One vehicle's details, with a switch between its fuel and maintenance logs.
/// A Stats tab arrives in a later step.
struct VehicleDetailView: View {
    let vehicle: Vehicle

    enum Log: String, CaseIterable, Identifiable {
        case fuel = "Fuel"
        case maintenance = "Maintenance"
        var id: Self { self }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var vehicleToDelete: Vehicle?
    @State private var isLoggingFuel = false
    @State private var editingFuelEntry: FuelEntry?
    @State private var isLoggingService = false
    @State private var editingServiceEntry: MaintenanceEntry?
    @State private var log: Log = .fuel

    var body: some View {
        List {
            Section {
                LabeledContent("Odometer", value: Units.miles(vehicle.currentOdometer))
                if let year = vehicle.year {
                    LabeledContent("Year", value: String(year))
                }
                if let make = vehicle.make {
                    LabeledContent("Make", value: make)
                }
                if let model = vehicle.model {
                    LabeledContent("Model", value: model)
                }
                if let vin = vehicle.vin {
                    LabeledContent("VIN") {
                        Text(vin)
                            .textSelection(.enabled)
                    }
                }
            }

            Picker("Log", selection: $log) {
                ForEach(Log.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            switch log {
            case .fuel:
                FuelHistorySection(
                    vehicle: vehicle,
                    onLog: { isLoggingFuel = true },
                    onEdit: { editingFuelEntry = $0 }
                )
            case .maintenance:
                MaintenanceHistorySection(
                    vehicle: vehicle,
                    onLog: { isLoggingService = true },
                    onEdit: { editingServiceEntry = $0 }
                )
            }

            Section {
                Button("Delete Vehicle", role: .destructive) {
                    vehicleToDelete = vehicle
                }
            }
        }
        .navigationTitle(vehicle.name)
        .toolbar {
            Button("Edit") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            VehicleFormView(vehicle: vehicle)
        }
        .sheet(isPresented: $isLoggingFuel) {
            FuelEntryFormView(vehicle: vehicle)
        }
        .sheet(item: $editingFuelEntry) { entry in
            FuelEntryFormView(vehicle: vehicle, entry: entry)
        }
        .sheet(isPresented: $isLoggingService) {
            MaintenanceEntryFormView(vehicle: vehicle)
        }
        .sheet(item: $editingServiceEntry) { entry in
            MaintenanceEntryFormView(vehicle: vehicle, entry: entry)
        }
        .deleteVehicleConfirmation(for: $vehicleToDelete) { vehicle in
            dismiss()
            modelContext.delete(vehicle)
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Vehicle.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let vehicle = Vehicle(name: "Project Car", year: 1994, make: "Mazda", model: "Miata", vin: "JM1NA3510R0512345", currentOdometer: 131_870)
    container.mainContext.insert(vehicle)
    return NavigationStack { VehicleDetailView(vehicle: vehicle) }
        .modelContainer(container)
}

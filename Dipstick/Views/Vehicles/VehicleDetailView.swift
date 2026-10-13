//
//  VehicleDetailView.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// One vehicle's details. Fuel, Maintenance and Stats sections arrive in later steps.
struct VehicleDetailView: View {
    let vehicle: Vehicle

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var vehicleToDelete: Vehicle?

    var body: some View {
        List {
            Section {
                LabeledContent("Odometer", value: "\(vehicle.currentOdometer.formatted()) mi")
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

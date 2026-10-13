//
//  VehicleListView.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Home screen: every vehicle. Swipe right to log a fill-up, left to delete.
struct VehicleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vehicle.name) private var vehicles: [Vehicle]

    @State private var isAdding = false
    @State private var vehicleToDelete: Vehicle?
    @State private var vehicleToFuel: Vehicle?

    var body: some View {
        NavigationStack {
            List {
                ForEach(vehicles) { vehicle in
                    NavigationLink(value: vehicle) {
                        VehicleRow(vehicle: vehicle)
                    }
                    .swipeActions(edge: .leading) {
                        Button("Log Fill-Up", systemImage: "fuelpump") {
                            vehicleToFuel = vehicle
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            vehicleToDelete = vehicle
                        }
                    }
                }
            }
            .overlay {
                if vehicles.isEmpty {
                    ContentUnavailableView {
                        Label("No Vehicles", systemImage: "car")
                    } description: {
                        Text("Add a car to start logging fuel and maintenance.")
                    } actions: {
                        Button("Add Vehicle") { isAdding = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Dipstick")
            .navigationDestination(for: Vehicle.self) { vehicle in
                VehicleDetailView(vehicle: vehicle)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Vehicle", systemImage: "plus") { isAdding = true }
                }
            }
            .sheet(isPresented: $isAdding) {
                VehicleFormView()
            }
            .sheet(item: $vehicleToFuel) { vehicle in
                FuelEntryFormView(vehicle: vehicle)
            }
            .deleteVehicleConfirmation(for: $vehicleToDelete) { vehicle in
                modelContext.delete(vehicle)
            }
        }
    }
}

private struct VehicleRow: View {
    let vehicle: Vehicle

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(vehicle.name)
                .font(.headline)
            if !vehicle.yearMakeModel.isEmpty {
                Text(vehicle.yearMakeModel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(Units.miles(vehicle.currentOdometer))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// Asks before deleting, since deleting a vehicle will also delete its fuel and
    /// maintenance history once those exist.
    func deleteVehicleConfirmation(
        for vehicle: Binding<Vehicle?>,
        onDelete: @escaping (Vehicle) -> Void
    ) -> some View {
        confirmationDialog(
            "Delete \(vehicle.wrappedValue?.name ?? "vehicle")?",
            isPresented: Binding(
                get: { vehicle.wrappedValue != nil },
                set: { if !$0 { vehicle.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: vehicle.wrappedValue
        ) { target in
            Button("Delete Vehicle", role: .destructive) { onDelete(target) }
        } message: { _ in
            Text("This also deletes all of its fuel and maintenance records. This can't be undone.")
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Vehicle.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    container.mainContext.insert(Vehicle(name: "Daily Driver", year: 2019, make: "Honda", model: "Civic", currentOdometer: 48_210))
    container.mainContext.insert(Vehicle(name: "Project Car", year: 1994, make: "Mazda", model: "Miata", currentOdometer: 131_870))
    return VehicleListView()
        .modelContainer(container)
}

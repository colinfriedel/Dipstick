//
//  VehicleListView.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Home screen: services due soon or overdue across all vehicles, then every
/// vehicle with its latest MPG and next service. Swipe a vehicle right to log a
/// fill-up or service, left to delete.
struct VehicleListView: View {
    /// A request to log a service, optionally for a specific service type.
    struct ServiceRequest: Identifiable {
        let id = UUID()
        let vehicle: Vehicle
        var serviceType: String?
    }

    /// One due/overdue service on one vehicle, for the Due section.
    private struct DueRow: Identifiable {
        let vehicle: Vehicle
        let item: MaintenanceDueCalculator.Item<PersistentIdentifier>
        var id: PersistentIdentifier { item.id }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Vehicle.name) private var vehicles: [Vehicle]

    @State private var isAdding = false
    @State private var vehicleToDelete: Vehicle?
    @State private var vehicleToFuel: Vehicle?
    @State private var serviceRequest: ServiceRequest?

    /// Everything due soon or overdue, most urgent first across all vehicles.
    private var dueRows: [DueRow] {
        vehicles
            .flatMap { vehicle in
                vehicle.maintenanceDueItems()
                    .filter { $0.status != .ok }
                    .map { DueRow(vehicle: vehicle, item: $0) }
            }
            .sorted { ($0.item.status, -$0.item.urgency) > ($1.item.status, -$1.item.urgency) }
    }

    var body: some View {
        NavigationStack {
            List {
                let due = dueRows
                if !due.isEmpty {
                    Section("Due") {
                        ForEach(due) { row in
                            Button {
                                serviceRequest = ServiceRequest(vehicle: row.vehicle, serviceType: row.item.serviceType)
                            } label: {
                                DueItemRow(vehicleName: row.vehicle.name, item: row.item)
                            }
                            .tint(.primary)
                        }
                    }
                }

                Section {
                    ForEach(vehicles) { vehicle in
                        NavigationLink(value: vehicle) {
                            VehicleRow(vehicle: vehicle)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Log Fill-Up", systemImage: "fuelpump") {
                                vehicleToFuel = vehicle
                            }
                            .tint(.green)
                            Button("Log Service", systemImage: "wrench.and.screwdriver") {
                                serviceRequest = ServiceRequest(vehicle: vehicle)
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                vehicleToDelete = vehicle
                            }
                        }
                    }
                } header: {
                    if !due.isEmpty { Text("Vehicles") }
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
            .sheet(item: $serviceRequest) { request in
                MaintenanceEntryFormView(vehicle: request.vehicle, serviceType: request.serviceType)
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
        let lastTank = vehicle.mpgSummary.latest
        let nextService = vehicle.maintenanceDueItems().first

        VStack(alignment: .leading, spacing: 2) {
            Text(vehicle.name)
                .font(.headline)
            if !vehicle.yearMakeModel.isEmpty {
                Text(vehicle.yearMakeModel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text([Units.miles(vehicle.currentOdometer), lastTank.map { "\(Units.mpg($0)) last tank" }]
                .compactMap { $0 }
                .joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let nextService {
                Text("Next: \(nextService.serviceType), \(nextService.summary)")
                    .font(.caption)
                    .foregroundStyle(nextService.status.color)
            }
        }
    }
}

private struct DueItemRow: View {
    let vehicleName: String
    let item: MaintenanceDueCalculator.Item<PersistentIdentifier>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.status.systemImage)
                .foregroundStyle(item.status.color)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.serviceType)
                    .font(.headline)
                Text("\(vehicleName) · \(item.summary)")
                    .font(.subheadline)
                    .foregroundStyle(item.status.color)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Logs this service")
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

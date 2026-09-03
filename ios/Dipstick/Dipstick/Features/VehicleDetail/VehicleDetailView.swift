import SwiftUI

/// Shows one vehicle's details, with Edit and Delete. The Fuel / Maintenance /
/// Stats tabs the spec calls for arrive in Milestone 6 (they need activity-service).
struct VehicleDetailView: View {
    @State private var vehicle: Vehicle
    @State private var showingEditForm = false
    @State private var confirmingDelete = false
    @State private var deleteError: String?

    @Environment(\.dismiss) private var dismiss

    /// Called after an edit or delete, so the list can refresh.
    let onChange: () -> Void
    private let repository: any VehicleRepository

    init(
        vehicle: Vehicle,
        repository: (any VehicleRepository)? = nil,
        onChange: @escaping () -> Void
    ) {
        _vehicle = State(initialValue: vehicle)
        self.repository = repository ?? AppEnvironment.vehicleRepository
        self.onChange = onChange
    }

    var body: some View {
        List {
            Section("Details") {
                LabeledContent("Name", value: vehicle.name)
                if let year = vehicle.year {
                    LabeledContent("Year", value: String(year))
                }
                if let make = vehicle.make, !make.isEmpty {
                    LabeledContent("Make", value: make)
                }
                if let model = vehicle.model, !model.isEmpty {
                    LabeledContent("Model", value: model)
                }
                if let vin = vehicle.vin, !vin.isEmpty {
                    LabeledContent("VIN", value: vin)
                }
                LabeledContent("Odometer", value: "\(vehicle.currentOdometer.formatted()) mi")
            }

            Section {
                Label("Fuel and maintenance logs arrive in the next milestone.",
                      systemImage: "hourglass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Delete Vehicle", role: .destructive) {
                    confirmingDelete = true
                }
            }
        }
        .navigationTitle(vehicle.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEditForm = true }
            }
        }
        .sheet(isPresented: $showingEditForm) {
            VehicleFormView(mode: .edit(vehicle)) { updated in
                vehicle = updated
                onChange()
            }
        }
        .confirmationDialog(
            "Delete \(vehicle.name)?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await performDelete() }
            }
        } message: {
            Text("This also removes its fuel and maintenance history. It can't be undone.")
        }
        .alert(
            "Couldn't delete",
            isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    private func performDelete() async {
        do {
            try await repository.delete(id: vehicle.id)
            onChange()
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        VehicleDetailView(vehicle: InMemoryVehicleRepository.sample[1],
                          repository: InMemoryVehicleRepository()) {}
    }
}

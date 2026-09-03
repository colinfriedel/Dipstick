import SwiftUI

/// One vehicle's screen: a compact header, then a Fuel / Maintenance / Stats
/// segmented view. Edit and Delete live in the toolbar menu.
struct VehicleDetailView: View {
    enum Tab: String, CaseIterable {
        case fuel = "Fuel"
        case maintenance = "Maintenance"
        case stats = "Stats"
    }

    @State private var vehicle: Vehicle
    @State private var tab: Tab = .fuel
    @State private var fuelViewModel: FuelLogViewModel
    @State private var maintenanceViewModel: MaintenanceLogViewModel

    @State private var showingEditForm = false
    @State private var confirmingDelete = false
    @State private var deleteError: String?

    @Environment(\.dismiss) private var dismiss

    /// Called after an edit or delete so the list can refresh.
    let onChange: () -> Void
    private let vehicleRepository: any VehicleRepository

    init(
        vehicle: Vehicle,
        vehicleRepository: (any VehicleRepository)? = nil,
        activityRepository: (any ActivityRepository)? = nil,
        onChange: @escaping () -> Void
    ) {
        _vehicle = State(initialValue: vehicle)
        _fuelViewModel = State(initialValue: FuelLogViewModel(vehicleID: vehicle.id, repository: activityRepository))
        _maintenanceViewModel = State(initialValue: MaintenanceLogViewModel(vehicleID: vehicle.id, repository: activityRepository))
        self.vehicleRepository = vehicleRepository ?? AppEnvironment.vehicleRepository
        self.onChange = onChange
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("View", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            switch tab {
            case .fuel:
                FuelLogView(viewModel: fuelViewModel)
            case .maintenance:
                MaintenanceLogView(viewModel: maintenanceViewModel)
            case .stats:
                VehicleStatsView(fuelViewModel: fuelViewModel)
            }
        }
        .navigationTitle(vehicle.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await fuelViewModel.load()
            await maintenanceViewModel.load()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit Details", systemImage: "pencil") { showingEditForm = true }
                    Button("Delete Vehicle", systemImage: "trash", role: .destructive) {
                        confirmingDelete = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !vehicle.descriptiveTitle.isEmpty {
                Text(vehicle.descriptiveTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("\(vehicle.currentOdometer.formatted()) mi")
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private func performDelete() async {
        do {
            try await vehicleRepository.delete(id: vehicle.id)
            onChange()
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        VehicleDetailView(
            vehicle: InMemoryVehicleRepository.sample[0],
            vehicleRepository: InMemoryVehicleRepository(),
            activityRepository: InMemoryActivityRepository()
        ) {}
    }
}

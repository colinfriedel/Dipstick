import SwiftUI

/// The app's home screen: the list of vehicles.
struct VehicleListView: View {
    @State private var viewModel: VehicleListViewModel
    @State private var showingAddForm = false

    init(viewModel: VehicleListViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? VehicleListViewModel())
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Vehicles")
                .navigationDestination(for: Vehicle.self) { vehicle in
                    VehicleDetailView(vehicle: vehicle) {
                        Task { await viewModel.load() }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingAddForm = true
                        } label: {
                            Label("Add Vehicle", systemImage: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showingAddForm) {
                    VehicleFormView(mode: .create) { _ in
                        Task { await viewModel.load() }
                    }
                }
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
                .alert(
                    "Something went wrong",
                    isPresented: Binding(
                        get: { viewModel.actionError != nil },
                        set: { if !$0 { viewModel.actionError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(viewModel.actionError ?? "")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.vehicles.isEmpty {
            ProgressView("Loading vehicles…")
        } else if let failure = viewModel.loadFailure, viewModel.vehicles.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load vehicles", systemImage: "wifi.exclamationmark")
            } description: {
                Text(failure)
            } actions: {
                Button("Try Again") { Task { await viewModel.load() } }
            }
        } else if viewModel.vehicles.isEmpty {
            ContentUnavailableView {
                Label("No vehicles yet", systemImage: "car")
            } description: {
                Text("Add your first vehicle to start tracking fuel and maintenance.")
            }
        } else {
            List {
                ForEach(viewModel.vehicles) { vehicle in
                    NavigationLink(value: vehicle) {
                        VehicleRow(vehicle: vehicle)
                    }
                }
                .onDelete { offsets in
                    let toDelete = offsets.map { viewModel.vehicles[$0] }
                    Task {
                        for vehicle in toDelete {
                            await viewModel.delete(vehicle)
                        }
                    }
                }
            }
        }
    }
}

private struct VehicleRow: View {
    let vehicle: Vehicle

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(vehicle.name)
                .font(.headline)
            if !vehicle.descriptiveTitle.isEmpty {
                Text(vehicle.descriptiveTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("\(vehicle.currentOdometer.formatted()) mi")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview("With vehicles") {
    VehicleListView(viewModel: VehicleListViewModel(repository: InMemoryVehicleRepository()))
}

#Preview("Empty") {
    VehicleListView(viewModel: VehicleListViewModel(repository: InMemoryVehicleRepository(vehicles: [])))
}

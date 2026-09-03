import SwiftUI

/// The Fuel tab of the vehicle detail screen. Its view model is created and
/// loaded by `VehicleDetailView`; this view just renders it and offers refresh
/// and add.
struct FuelLogView: View {
    let viewModel: FuelLogViewModel
    @State private var showingForm = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.entries.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let failure = viewModel.loadFailure, viewModel.entries.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load the fuel log", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Try Again") { Task { await viewModel.load() } }
                }
            } else if viewModel.entries.isEmpty {
                ContentUnavailableView(
                    "No fill-ups yet",
                    systemImage: "fuelpump",
                    description: Text("Log a fill-up to start tracking MPG.")
                )
            } else {
                List(viewModel.entries) { entry in
                    FuelEntryRow(entry: entry)
                }
                .listStyle(.plain)
            }
        }
        .refreshable { await viewModel.load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingForm = true
                } label: {
                    Label("Log Fill-up", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingForm) {
            FuelEntryFormView(vehicleID: viewModel.vehicleID) {
                Task { await viewModel.load() }
            }
        }
    }
}

private struct FuelEntryRow: View {
    let entry: FuelEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(entry.date.displayString).font(.headline)
                Spacer()
                mpgBadge
            }
            HStack(spacing: 14) {
                Label("\(entry.gallons, format: .oneDecimal) gal", systemImage: "fuelpump")
                Text(entry.totalCost, format: .money)
                Text("\(entry.costPerGallon, format: .money)/gal")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let station = entry.stationName {
                Text(station).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var mpgBadge: some View {
        if let mpg = entry.mpg {
            Text("\(mpg, format: .oneDecimal) MPG")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
        } else if !entry.isFullTank {
            Text("partial — not used for MPG")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        FuelLogView(viewModel: {
            let vm = FuelLogViewModel(vehicleID: 1, repository: InMemoryActivityRepository())
            Task { await vm.load() }
            return vm
        }())
    }
}

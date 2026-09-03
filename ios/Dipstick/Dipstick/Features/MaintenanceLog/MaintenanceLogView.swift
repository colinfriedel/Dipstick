import SwiftUI

/// The Maintenance tab of the vehicle detail screen.
struct MaintenanceLogView: View {
    let viewModel: MaintenanceLogViewModel
    @State private var showingForm = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.entries.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let failure = viewModel.loadFailure, viewModel.entries.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load the maintenance log", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Try Again") { Task { await viewModel.load() } }
                }
            } else if viewModel.entries.isEmpty {
                ContentUnavailableView(
                    "No services logged",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Log a service to keep a maintenance history.")
                )
            } else {
                List(viewModel.entries) { entry in
                    MaintenanceEntryRow(entry: entry)
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
                    Label("Log Service", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingForm) {
            MaintenanceEntryFormView(vehicleID: viewModel.vehicleID) {
                Task { await viewModel.load() }
            }
        }
    }
}

private struct MaintenanceEntryRow: View {
    let entry: MaintenanceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(entry.serviceType).font(.headline)
                Spacer()
                Text(entry.date.displayString).font(.subheadline).foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Label("\(entry.odometer.formatted()) mi", systemImage: "gauge")
                if entry.cost > 0 {
                    Text(entry.cost, format: .money)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let parts = entry.partsUsed, !parts.isEmpty {
                Text(parts.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let nextDue = nextDueText {
                Text(nextDue)
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 3)
    }

    private var nextDueText: String? {
        var parts: [String] = []
        if let mi = entry.nextDueOdometer { parts.append("\(mi.formatted()) mi") }
        if let date = entry.nextDueDate { parts.append(date.displayString) }
        return parts.isEmpty ? nil : "Next due: " + parts.joined(separator: " or ")
    }
}

#Preview {
    NavigationStack {
        MaintenanceLogView(viewModel: {
            let vm = MaintenanceLogViewModel(vehicleID: 1, repository: InMemoryActivityRepository())
            Task { await vm.load() }
            return vm
        }())
    }
}

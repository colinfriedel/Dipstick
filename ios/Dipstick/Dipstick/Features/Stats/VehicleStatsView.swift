import SwiftUI

/// The Stats tab. Reads the same `FuelLogViewModel` the Fuel tab uses, so there's
/// no extra fetch. Shows the headline numbers; the trend chart lands in M9.
struct VehicleStatsView: View {
    let fuelViewModel: FuelLogViewModel

    private var stats: FuelStats {
        FuelStats(entries: fuelViewModel.entries)
    }

    var body: some View {
        Group {
            if fuelViewModel.isLoading && fuelViewModel.entries.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if fuelViewModel.entries.isEmpty {
                ContentUnavailableView(
                    "No stats yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Log a few fill-ups and stats will show up here.")
                )
            } else {
                List {
                    Section("Fuel economy") {
                        statRow("Average MPG", value: stats.averageMPG.map { "\($0.formatted(.oneDecimal))" } ?? "—")
                        statRow("Best tank", value: stats.bestMPG.map { "\($0.formatted(.oneDecimal)) MPG" } ?? "—")
                    }
                    Section("Spending") {
                        statRow("This year", value: stats.totalSpendThisYear.formatted(.money))
                        statRow("All time", value: stats.totalSpendAllTime.formatted(.money))
                        statRow("Fill-ups logged", value: "\(stats.fillUpCount)")
                    }
                    Section {
                        Label("An MPG trend chart is coming in a later milestone.",
                              systemImage: "chart.xyaxis.line")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .refreshable { await fuelViewModel.load() }
    }

    private func statRow(_ label: String, value: String) -> some View {
        LabeledContent(label) {
            Text(value).font(.body.weight(.medium))
        }
    }
}

#Preview {
    NavigationStack {
        VehicleStatsView(fuelViewModel: {
            let vm = FuelLogViewModel(vehicleID: 1, repository: InMemoryActivityRepository())
            Task { await vm.load() }
            return vm
        }())
    }
}

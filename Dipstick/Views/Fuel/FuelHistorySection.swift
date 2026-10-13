//
//  FuelHistorySection.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Fuel part of the vehicle detail list: average MPG, a log button, and every
/// fill-up newest first. Tap a row to edit it, swipe to delete.
///
/// The parent presents the log/edit sheets: a `.sheet` attached to a `Section`
/// is copied onto every row, and the copies fight over presenting.
struct FuelHistorySection: View {
    let vehicle: Vehicle
    let onLog: () -> Void
    let onEdit: (FuelEntry) -> Void

    @Environment(\.modelContext) private var modelContext

    private var entries: [FuelEntry] {
        (vehicle.fuelEntries ?? []).sorted {
            ($0.date, $0.odometer) > ($1.date, $1.odometer)
        }
    }

    var body: some View {
        let fills = entries.map(\.fill)
        let mpgResults = MPGCalculator.results(for: fills)

        Section {
            if let lastTank = MPGCalculator.latest(in: fills, results: mpgResults) {
                LabeledContent("Last tank", value: Units.mpg(lastTank.mpg))
            }
            if let average = MPGCalculator.average(of: mpgResults.values) {
                LabeledContent("Average", value: Units.mpg(average))
            }
            Button("Log Fill-Up", systemImage: "fuelpump", action: onLog)

            ForEach(entries) { entry in
                Button { onEdit(entry) } label: {
                    FuelEntryRow(entry: entry, result: mpgResults[entry.persistentModelID])
                }
                .tint(.primary)
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        modelContext.delete(entry)
                    }
                }
            }
        } header: {
            Text("Fuel")
        } footer: {
            if entries.isEmpty {
                Text("No fill-ups yet. MPG appears once you've logged two full tanks.")
            }
        }
    }
}

private struct FuelEntryRow: View {
    let entry: FuelEntry
    let result: MPGCalculator.Result?

    /// Miles driven on this tank (since the previous full tank), the same
    /// distance its MPG is based on.
    private var tankMiles: String? {
        result.map { "\($0.miles.formatted()) mi" }
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.headline)

                HStack {
                    Text(Units.gallons(entry.gallons))
                    Text("·")
                    Text(entry.isCostKnown ? Units.currency(entry.totalCost) : "cost —")
                    if let price = entry.pricePerGallon {
                        Text("·")
                        Text(Units.pricePerGallon(price))
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                HStack {
                    Text(Units.miles(entry.odometer))
                    if !entry.isFullTank {
                        Text("· Partial fill, not used for MPG")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let result {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Units.mpg(result.mpg))
                        .font(.headline)
                    if let tankMiles {
                        Text(tankMiles)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .monospacedDigit()
            }
        }
    }
}

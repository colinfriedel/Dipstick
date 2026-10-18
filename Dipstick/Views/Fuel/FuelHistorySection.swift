//
//  FuelHistorySection.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Fuel tab of vehicle detail (design board D / N): RECENT · ALL-TIME ·
/// COST / MI tiles, LOG FILL-UP, then every fill-up newest first. Tap a
/// fill-up to edit it, swipe to delete.
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
        let entries = entries
        let fills = entries.map(\.fill)
        let mpgResults = MPGCalculator.results(for: fills)
        let stats = vehicle.fuelStats()
        let lastTank = MPGCalculator.latest(in: fills, results: mpgResults)

        Section {
            TileRow {
                ReadoutTile("Recent") { MPGReadout(value: stats.recentMPG) }
                ReadoutTile("All-time", highlighted: true) {
                    MPGReadout(value: stats.averageMPG, color: Theme.accent)
                }
                ReadoutTile("Cost / mi") {
                    MonoNumber(text: stats.costPerMile.map { String(format: "$%.2f", $0) } ?? "--",
                               size: 30, color: stats.costPerMile == nil ? Theme.gaugeEmpty : Theme.text)
                }
            }
            .plainRow(top: 12, bottom: 6)

            Button(action: onLog) {
                Label("Log fill-up", systemImage: "fuelpump")
            }
            .buttonStyle(BigActionButtonStyle(height: 60))
            .plainRow(top: 10, bottom: 10)

            SectionTitle("Fill-ups") {
                if let average = stats.averageMPG, let lastTank {
                    Text("Avg \(String(format: "%.1f", average)) · Last tank \(String(format: "%.1f", lastTank.mpg)) mpg")
                        .font(.dipstick(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
            }
            .plainRow(top: 8, bottom: 6)

            if entries.isEmpty {
                Text("No fill-ups yet. MPG appears once you've logged two full tanks.")
                    .font(.dipstick(14, relativeTo: .subheadline))
                    .foregroundStyle(Theme.muted)
                    .panelRow(.only)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    Button { onEdit(entry) } label: {
                        FuelEntryRow(entry: entry, result: mpgResults[entry.persistentModelID])
                    }
                    .buttonStyle(.borderless)
                    .panelRow(.of(index, count: entries.count))
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            modelContext.delete(entry)
                            modelContext.saveNow()
                        }
                        .tint(Theme.red)
                    }
                }
            }
        }
    }
}

private struct FuelEntryRow: View {
    let entry: FuelEntry
    let result: MPGCalculator.Result?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.date, format: .dateTime.month(.abbreviated).day().year())
                    .multilineTextAlignment(.leading)
                    .font(.dipstick(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)

                Group {
                    Text(details)
                    Text(Units.miles(entry.odometer))
                }
                .font(.dipstick(12, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                if let result {
                    MPGReadout(value: result.mpg, size: 26)
                    Text("\(result.miles.formatted()) mi")
                        .font(.dipstick(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                } else if !entry.isFullTank {
                    Text("partial fill,\nnot used for MPG")
                        .font(.dipstick(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit this fill-up")
    }

    /// "9.768 gal · $60.06 · $6.149/gal" (cost and price only when known).
    private var details: String {
        var parts = [Units.gallons(entry.gallons)]
        if entry.isCostKnown {
            parts.append(Units.currency(entry.totalCost))
            if let price = entry.pricePerGallon { parts.append(Units.pricePerGallon(price)) }
        } else {
            parts.append("cost —")
        }
        return parts.joined(separator: " · ")
    }
}

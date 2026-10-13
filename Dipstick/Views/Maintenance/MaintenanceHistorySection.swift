//
//  MaintenanceHistorySection.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Maintenance part of the vehicle detail list: a log button, search and a
/// service-type filter, then every record newest first. The parent presents
/// the sheets (see `FuelHistorySection` for why).
struct MaintenanceHistorySection: View {
    let vehicle: Vehicle
    let onLog: () -> Void
    let onEdit: (MaintenanceEntry) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var query = ""
    @State private var typeFilter: String?
    @FocusState private var isSearching: Bool

    private var entries: [MaintenanceEntry] {
        (vehicle.maintenanceEntries ?? []).sorted {
            ($0.date, $0.odometer) > ($1.date, $1.odometer)
        }
    }

    private var typesInUse: [String] {
        Array(Set(entries.map(\.serviceType)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        let all = entries
        let shown = all.filter { $0.matches(query: query, typeFilter: typeFilter) }
        let dueByEntry = Dictionary(uniqueKeysWithValues: vehicle.maintenanceDueItems().map { ($0.id, $0) })

        Section {
            Button("Log Service", systemImage: "wrench.and.screwdriver") {
                isSearching = false
                onLog()
            }

            if !all.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search services, parts, notes", text: $query)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($isSearching)
                    if !query.isEmpty {
                        Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.borderless)
                    }
                    Menu {
                        Picker("Service", selection: $typeFilter) {
                            Text("All services").tag(String?.none)
                            ForEach(typesInUse, id: \.self) { Text($0).tag(Optional($0)) }
                        }
                    } label: {
                        Image(systemName: typeFilter == nil
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filter by service")
                }
            }

            ForEach(shown) { entry in
                Button {
                    // Otherwise the search field grabs focus again when the sheet closes.
                    isSearching = false
                    onEdit(entry)
                } label: {
                    MaintenanceEntryRow(entry: entry, dueItem: dueByEntry[entry.persistentModelID])
                }
                .tint(.primary)
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        modelContext.delete(entry)
                    }
                }
            }
        } header: {
            Text("Maintenance")
        } footer: {
            if all.isEmpty {
                Text("No services logged yet.")
            } else if shown.isEmpty {
                Text("No services match.")
            } else if typeFilter != nil || !query.isEmpty {
                Text("Showing \(shown.count) of \(all.count).")
            }
        }
    }
}

private struct MaintenanceEntryRow: View {
    let entry: MaintenanceEntry
    /// Set only when this is the latest record of its service type and it has a
    /// next-due; older records' due dates no longer apply.
    let dueItem: MaintenanceDueCalculator.Item<PersistentIdentifier>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.serviceType)
                    .font(.headline)
                Spacer()
                Text(Units.currency(entry.cost))
                    .font(.headline)
                    .monospacedDigit()
            }
            Text("\(entry.date.formatted(date: .abbreviated, time: .omitted)) · \(Units.miles(entry.odometer))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let partNames = entry.sortedParts.map(\.name)
            if !partNames.isEmpty {
                Text(partNames.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let notes = entry.notes {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let dueItem, let due = dueItem.due.summary {
                Label("Next: \(due) · \(dueItem.summary)", systemImage: dueItem.status.systemImage)
                    .font(.caption)
                    .foregroundStyle(dueItem.status.color)
            }
        }
    }
}

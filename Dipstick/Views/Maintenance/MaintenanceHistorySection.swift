//
//  MaintenanceHistorySection.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Maintenance tab of vehicle detail (design board E / O): LOG SERVICE, a
/// link to the factory schedule, search and a filter, a chip row of this
/// car's service types (scheduled ones first), then every
/// record newest first. The latest record of each type shows when it's next
/// due. Tap a record to edit it, swipe to delete. The parent presents the
/// sheets (see `FuelHistorySection` for why).
struct MaintenanceHistorySection: View {
    let vehicle: Vehicle
    let onLog: () -> Void
    let onEdit: (MaintenanceEntry) -> Void
    let onSchedule: () -> Void
    /// Opens a service type's past notes and photos.
    let onReference: (String) -> Void
    /// Import records from photos, PDFs or spreadsheets.
    let onImport: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var query = ""
    @State private var typeFilter: String?
    @FocusState private var isSearching: Bool

    private var entries: [MaintenanceEntry] {
        (vehicle.maintenanceEntries ?? []).sorted {
            ($0.date, $0.odometer) > ($1.date, $1.odometer)
        }
    }

    /// This car's service types: those on its factory schedule first (in the
    /// manual's order), then the rest most recently done first.
    private var typesInUse: [String] {
        var seen = Set<String>()
        let byRecency = entries.map(\.serviceType).filter { seen.insert($0.lowercased()).inserted }
        return FactorySchedule.scheduleFirst(byRecency, schedule: vehicle.sortedScheduleItems.map(\.serviceType))
    }

    var body: some View {
        let all = entries
        let shown = all.filter { $0.matches(query: query, typeFilter: typeFilter) }
        let dueByEntry = Dictionary(uniqueKeysWithValues: vehicle.maintenanceDueItems().map { ($0.id, $0) })

        Section {
            Button {
                isSearching = false
                onLog()
            } label: {
                Label("Log service", systemImage: "wrench.adjustable")
            }
            .buttonStyle(BigActionButtonStyle(height: 56))
            .plainRow(top: 12, bottom: 8)

            scheduleLink.plainRow(top: 0, bottom: 8)

            if !all.isEmpty {
                searchRow.plainRow(top: 4, bottom: 4)
                chipRow.plainRow(top: 4, bottom: 8)
                if let typeFilter, vehicle.hasPastServiceNotes(ofType: typeFilter) {
                    ServiceNotesLink(vehicle: vehicle, serviceType: typeFilter) {
                        isSearching = false
                        onReference(typeFilter)
                    }
                    .plainRow(top: 0, bottom: 8)
                }
            }

            if all.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No services logged yet.")
                        .font(.dipstick(14, relativeTo: .subheadline))
                        .foregroundStyle(Theme.muted)
                    Button {
                        isSearching = false
                        onImport()
                    } label: {
                        Label("Import past records", systemImage: "doc.text.viewfinder")
                            .font(.dipstick(14, .semibold, relativeTo: .body))
                            .foregroundStyle(Theme.accentText)
                    }
                    .buttonStyle(.borderless)
                    Text("From photos or screenshots of invoices, a Carfax report, a PDF or a spreadsheet.")
                        .font(.dipstick(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 4)
                .panelRow(.only)
            } else if shown.isEmpty {
                Text("No services match.")
                    .font(.dipstick(14, relativeTo: .subheadline))
                    .foregroundStyle(Theme.muted)
                    .panelRow(.only)
            } else {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        // Otherwise the search field grabs focus again when the sheet closes.
                        isSearching = false
                        onEdit(entry)
                    } label: {
                        MaintenanceEntryRow(entry: entry, dueItem: dueByEntry[entry.persistentModelID])
                    }
                    .buttonStyle(.borderless)
                    .panelRow(.of(index, count: shown.count))
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

    /// Opens the factory schedule, with how many items need attention.
    private var scheduleLink: some View {
        let progress = vehicle.sortedScheduleItems.compactMap { vehicle.scheduleProgress(for: $0) }
            .filter { !$0.needsRecord }
        let worst = progress.map(\.status).max() ?? .ok
        let attention = progress.filter { $0.status != .ok }.count
        let summary = progress.isEmpty && (vehicle.scheduleItems ?? []).isEmpty
            ? "Set up"
            : attention > 0 ? "\(attention) need\(attention == 1 ? "s" : "") attention" : "All on track"

        return Button {
            isSearching = false
            onSchedule()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Text("Factory schedule")
                    .font(.dipstick(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                Text(summary)
                    .font(.dipstick(12, .semibold, relativeTo: .caption))
                    .foregroundStyle(attention > 0 ? worst.tint : Theme.muted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .panel(radius: Theme.Radius.field)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.muted)
                TextField("Search services, parts, notes", text: $query,
                          prompt: Text("Search services, parts, notes").foregroundStyle(Theme.faint))
                    .font(.dipstick(14, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearching)
                if !query.isEmpty {
                    Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.muted)
                        .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .panel(radius: Theme.Radius.field)

            Menu {
                Picker("Service", selection: $typeFilter) {
                    Text("All services").tag(String?.none)
                    ForEach(typesInUse, id: \.self) { Text($0).tag(Optional($0)) }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(typeFilter == nil ? Theme.text : Theme.accent)
                    .frame(width: 48, height: 48)
                    .panel(radius: Theme.Radius.field,
                           border: typeFilter == nil ? Theme.panelBorder : Theme.accent)
            }
            .accessibilityLabel("Filter by service")
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ChipButton(title: "All", isSelected: typeFilter == nil) { typeFilter = nil }
                ForEach(typesInUse, id: \.self) { type in
                    ChipButton(title: type, isSelected: typeFilter == type) {
                        typeFilter = typeFilter == type ? nil : type
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }
}

struct MaintenanceEntryRow: View {
    let entry: MaintenanceEntry
    /// Set only when this is the latest record of its service type and it has a
    /// next-due; older records' due dates no longer apply.
    let dueItem: MaintenanceDueCalculator.Item<PersistentIdentifier>?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.serviceType)
                    .font(.dipstick(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                Text("\(entry.date.formatted(.dateTime.month(.abbreviated).day().year())) · \(Units.miles(entry.odometer))")
                    .font(.dipstick(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
                if let detail {
                    Text(detail)
                        .font(.dipstick(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                if let dueItem {
                    StatusLine(status: dueItem.status, text: "\(dueItem.nextLabel) · \(dueItem.shortSummary)")
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 8)
            if entry.cost > 0 {
                MonoNumber(text: Units.currency(entry.cost), size: 15)
            }
        }
        .multilineTextAlignment(.leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit this service")
    }

    /// Parts used, or the notes when there are no parts.
    private var detail: String? {
        let parts = entry.sortedParts.map(\.summary)
        if !parts.isEmpty { return parts.joined(separator: ", ") }
        return entry.notes
    }
}

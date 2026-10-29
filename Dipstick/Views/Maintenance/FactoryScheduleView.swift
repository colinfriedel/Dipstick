//
//  FactoryScheduleView.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// The car's factory maintenance schedule as a chart: one bar per item
/// showing how far it is from the last time it was logged to the next time
/// it's due, most urgent first. Items never logged are listed separately.
/// Tap an item for its history, to log it, or to edit it.
struct FactoryScheduleView: View {
    let vehicle: Vehicle

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var openItem: ScheduleItem?
    @State private var isAdding = false
    @State private var isConfirmingClear = false
    @State private var isReadingManual = false

    private struct Row: Identifiable {
        let item: ScheduleItem
        let progress: FactorySchedule.Progress?
        var id: PersistentIdentifier { item.persistentModelID }
    }

    var body: some View {
        let rows = vehicle.sortedScheduleItems.map { Row(item: $0, progress: vehicle.scheduleProgress(for: $0)) }
        let charted = rows
            .filter { $0.progress.map { !$0.needsRecord } ?? false }
            .sorted { a, b in
                let (pa, pb) = (a.progress!, b.progress!)
                if pa.status != pb.status { return pa.status > pb.status }
                return (pa.fraction ?? 0) > (pb.fraction ?? 0)
            }
        let unlogged = rows.filter { $0.progress?.needsRecord ?? false }
        let untimed = rows.filter { $0.progress == nil }

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                navRow.padding(.bottom, 2)
                header.padding(.bottom, 6)

                if rows.isEmpty {
                    emptyState
                } else {
                    if vehicle.hasStandardSchedule { standardBanner }
                    if !charted.isEmpty {
                        SectionTitle("By urgency") {
                            Text("Since last logged")
                                .font(.dipstick(11.5, relativeTo: .caption))
                                .foregroundStyle(Theme.muted)
                        }
                        PanelList(charted) { row in
                            itemButton(row.item) { ScheduleChartRow(item: row.item, progress: row.progress!) }
                        }
                    }
                    if !unlogged.isEmpty {
                        SectionTitle("Not logged yet") {
                            Text("Log it to start tracking")
                                .font(.dipstick(11.5, relativeTo: .caption))
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(.top, 8)
                        PanelList(unlogged) { row in
                            itemButton(row.item) { ScheduleTextRow(item: row.item, progress: row.progress) }
                        }
                    }
                    if !untimed.isEmpty {
                        SectionTitle("Ongoing").padding(.top, 8)
                        PanelList(untimed) { row in
                            itemButton(row.item) { ScheduleTextRow(item: row.item, progress: nil) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $openItem) { item in
            ScheduleItemDetailView(vehicle: vehicle, item: item)
        }
        .fullScreenCover(isPresented: $isAdding) {
            ScheduleItemFormView(vehicle: vehicle)
        }
        .confirmationDialog("Remove every item from this car's schedule?",
                            isPresented: $isConfirmingClear, titleVisibility: .visible) {
            Button("Clear Schedule", role: .destructive) {
                for item in vehicle.scheduleItems ?? [] { modelContext.delete(item) }
                modelContext.saveNow()
            }
        } message: {
            Text("Logged services aren't affected.")
        }
        .fullScreenCover(isPresented: $isReadingManual) {
            ScheduleImportView(vehicle: vehicle)
        }
    }

    private func itemButton<Label: View>(_ item: ScheduleItem, @ViewBuilder label: () -> Label) -> some View {
        Button { openItem = item } label: {
            HStack(spacing: 10) {
                label()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows its history")
    }

    // MARK: Header

    private var navRow: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(SmallControlButtonStyle())
            .accessibilityLabel("Back")

            Spacer()

            Button { isAdding = true } label: {
                Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(SmallControlButtonStyle(foreground: Theme.accent))
            .accessibilityLabel("Add schedule item")

            Menu {
                Button("Read from Owner's Manual…", systemImage: "doc.text.viewfinder") { isReadingManual = true }
                Button("Use Standard Schedule", systemImage: "arrow.counterclockwise") { load(standardPreset) }
                presetButtons
                if !(vehicle.scheduleItems ?? []).isEmpty {
                    Divider()
                    Button("Clear Schedule", systemImage: "trash", role: .destructive) { isConfirmingClear = true }
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(SmallControlButtonStyle())
            .accessibilityLabel("More")
        }
    }

    @ViewBuilder
    private var presetButtons: some View {
        ForEach(FactorySchedule.presets) { preset in
            Button("Load \(preset.name)", systemImage: "square.and.arrow.down") { load(preset) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                vehicle.chip
                Text("FACTORY SCHEDULE")
                    .font(.dipstick(22, .semibold, relativeTo: .title))
                    .tracking(2)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
            }
            Text("\(vehicle.name) · \(Units.miles(vehicle.currentOdometer)) · whichever comes first")
                .font(.dipstick(13, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
        }
    }

    /// On the standard schedule: say what it is, and that it can be changed.
    private var standardBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(Theme.muted)
                Text("Standard schedule")
                    .font(.dipstick(14, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
            }
            Text("Routine intervals for \(FactorySchedule.Era(year: vehicle.year).label)\(vehicle.year == nil ? " (add the year in Edit to match yours)" : ""). If your owner's manual, dealer or mechanic gives different ones, tap an item, then Edit, to change it, or remove any that don't apply.")
                .font(.dipstick(13, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button { isReadingManual = true } label: {
                Label("Have your car's schedule? Read it from the manual", systemImage: "doc.text.viewfinder")
                    .font(.dipstick(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Theme.accentText)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(radius: Theme.Radius.field)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start from routine intervals that suit most cars, then change any to match your car's schedule.")
                .font(.dipstick(14, relativeTo: .body))
                .foregroundStyle(Theme.muted)
            Button { load(standardPreset) } label: {
                Label("Use the standard schedule", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(BigActionButtonStyle(height: 56))
            Button { isReadingManual = true } label: {
                Label("Read from owner's manual", systemImage: "doc.text.viewfinder")
                    .font(.dipstick(14, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            ForEach(FactorySchedule.presets) { preset in
                Button { load(preset) } label: {
                    Label("Load \(preset.name)", systemImage: "square.and.arrow.down")
                        .font(.dipstick(14, .semibold, relativeTo: .body))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            Button { isAdding = true } label: {
                Label("Add item", systemImage: "plus")
                    .font(.dipstick(14, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    /// A preset replaces the standard schedule (or an empty one), and is
    /// added after the car's own items otherwise.
    /// The standard schedule for this car's model year.
    private var standardPreset: FactorySchedule.Preset { FactorySchedule.standard(forYear: vehicle.year) }

    private func load(_ preset: FactorySchedule.Preset) {
        let source = preset.id == standardPreset.id ? FactorySchedule.standardSource : preset.name
        if vehicle.hasStandardSchedule || (vehicle.scheduleItems ?? []).isEmpty {
            vehicle.replaceSchedule(with: preset.items, source: source, in: modelContext)
        } else {
            vehicle.loadSchedule(preset, into: modelContext)
        }
        modelContext.saveNow()
    }
}

// MARK: - Rows

/// Name and status on top, the progress bar, then the interval and last time.
struct ScheduleChartRow: View {
    let item: ScheduleItem
    let progress: FactorySchedule.Progress
    /// Off on the item's own page, where the name is the title.
    var showsName = true

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                if showsName {
                    Text(item.name)
                        .font(.dipstick(15, .semibold, relativeTo: .body))
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                }
                Text(progress.shortSummary.uppercased())
                    .font(.readout(13, relativeTo: .caption))
                    .foregroundStyle(progress.status == .ok ? Theme.muted : progress.status.tint)
                    .fixedSize()
            }
            ScheduleBar(fraction: progress.fraction ?? 0, status: progress.status)
            Text(detail)
                .font(.dipstick(12, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue("\(progress.shortSummary). \(detail)")
    }

    private var detail: String {
        let last = progress.lastDone.map {
            "Last \($0.date.formatted(.dateTime.month(.abbreviated).year())) at \($0.odometer.formatted()) mi"
        } ?? "From new"
        let interval = item.effectiveRule.summary.map { item.hasCustomInterval ? "\($0) (yours)" : $0 }
        return [interval, last, progress.dueLabel].compactMap { $0 }.joined(separator: " · ")
    }
}

/// For items with no bar: never logged, or no interval at all.
struct ScheduleTextRow: View {
    let item: ScheduleItem
    let progress: FactorySchedule.Progress?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.dipstick(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                if let summary = item.effectiveRule.summary ?? item.note {
                    Text(summary)
                        .font(.dipstick(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
                if let progress, let due = progress.due.odometer {
                    StatusLine(status: progress.status, text: "First due at \(due.formatted()) mi")
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 8)
            Text(item.serviceType)
                .font(.dipstick(12, relativeTo: .caption))
                .foregroundStyle(Theme.faint)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A horizontal gauge: fills toward due, full and red once overdue.
struct ScheduleBar: View {
    let fraction: Double
    let status: MaintenanceDueCalculator.Status

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.divider)
                Capsule()
                    .fill(color)
                    .frame(width: max(proxy.size.width * min(fraction, 1), fraction > 0 ? 6 : 0))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private var color: Color {
        switch status {
        case .ok: Theme.accent
        case .dueSoon: Theme.amber
        case .overdue: Theme.red
        }
    }
}

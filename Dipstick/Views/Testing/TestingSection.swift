//
//  TestingSection.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// The Testing side of the Maintenance tab: LOG TEST, every test this car
/// can have (built-in and custom) with when it was last done and any
/// reminder, then every test logged, newest first. Tap a test type for its
/// page (history, chart, spec, notes and photos); tap a logged test to edit
/// it, swipe to delete. The parent presents the sheets.
struct TestingSection: View {
    let vehicle: Vehicle
    let onLog: () -> Void
    let onEdit: (TestEntry) -> Void
    let onOpenType: (String) -> Void

    @Environment(\.modelContext) private var modelContext

    private var entries: [TestEntry] {
        (vehicle.testEntries ?? []).sorted { ($0.date, $0.odometer) > ($1.date, $1.odometer) }
    }

    var body: some View {
        let all = entries
        let types = TestTemplate.options(addingUsed: all.map(\.testType))

        Section {
            Button(action: onLog) {
                Label("Log test", systemImage: "gauge.with.dots.needle.50percent")
            }
            .buttonStyle(BigActionButtonStyle(height: 56))
            .plainRow(top: 12, bottom: 8)

            SectionTitle("Tests and inspections") {
                Text("Tap for history, spec and notes")
                    .font(.dipstick(11.5, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
            .plainRow(top: 8, bottom: 4)
            ForEach(Array(types.enumerated()), id: \.element) { index, type in
                Button { onOpenType(type) } label: {
                    TestTypeRow(vehicle: vehicle, type: type)
                }
                .buttonStyle(.borderless)
                .panelRow(.of(index, count: types.count))
            }

            SectionTitle("History") {
                Text(all.isEmpty ? "None yet" : "\(all.count) logged")
                    .font(.dipstick(11.5, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
            .plainRow(top: 16, bottom: 4)
            if all.isEmpty {
                Text("Log a test to keep its readings and compare them next time.")
                    .font(.dipstick(14, relativeTo: .subheadline))
                    .foregroundStyle(Theme.muted)
                    .panelRow(.only)
            } else {
                ForEach(Array(all.enumerated()), id: \.element.id) { index, entry in
                    Button { onEdit(entry) } label: {
                        TestEntryRow(entry: entry, page: vehicle.referencePage(kind: ReferencePage.testKind,
                                                                              name: entry.testType))
                    }
                    .buttonStyle(.borderless)
                    .panelRow(.of(index, count: all.count))
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

/// A test type: its name, then when it was last done or when it's due.
struct TestTypeRow: View {
    let vehicle: Vehicle
    let type: String

    var body: some View {
        let last = vehicle.tests(ofType: type).first
        let reminder = vehicle.testReminder(for: type)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(type)
                    .font(.dipstick(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                if let reminder, reminder.status != .ok {
                    StatusLine(status: reminder.status,
                               text: reminder.lastDone == nil ? "Not done yet" : reminder.shortSummary)
                } else {
                    Text(last.map { "Last \($0.date.formatted(.dateTime.month(.abbreviated).day().year())) · \(Units.miles($0.odometer))" }
                         ?? "Not done yet")
                        .font(.dipstick(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.faint)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A logged test: type, date and odometer, its readings, and a warning if
/// any are outside the spec.
struct TestEntryRow: View {
    let entry: TestEntry
    var page: ReferencePage?
    var showsType = true

    var body: some View {
        let problems = entry.specProblems(page: page)
        VStack(alignment: .leading, spacing: 3) {
            if showsType {
                Text(entry.testType)
                    .font(.dipstick(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
            }
            Text("\(entry.date.formatted(.dateTime.month(.abbreviated).day().year())) · \(Units.miles(entry.odometer))")
                .font(.dipstick(showsType ? 12 : 14, showsType ? .medium : .semibold, relativeTo: .caption))
                .foregroundStyle(showsType ? Theme.muted : Theme.text)
            if let summary = entry.summary {
                Text(summary)
                    .font(.readout(13, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            if !problems.isEmpty {
                StatusLine(status: .overdue, text: "\(problems.count) out of spec")
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension TestEntry {
    /// Readings outside the reference page's spec, by reading.
    func specProblems(page: ReferencePage?) -> [PersistentIdentifier: String] {
        guard let page, page.hasSpec else { return [:] }
        let template = TestTemplate.template(named: testType)
        let labels = Set(template?.labels(cylinders: 12) ?? [])
        // Built-in rows are checked; for custom tests, every numbered reading.
        let checked = sortedReadings.filter { template == nil || labels.contains($0.label) }
        let spec = TestSpec.Spec(min: page.specMin, max: page.specMax, maxSpread: page.specMaxSpread)
        let found = TestSpec.problems(checked.map(\.value), spec: spec)
        return Dictionary(uniqueKeysWithValues: found.map { (checked[$0.key].persistentModelID, $0.value) })
    }
}

extension Vehicle {
    /// When a test is due, if it has a reminder interval on its reference
    /// page. Never done counts as due now.
    func testReminder(for type: String, today: Date = Date()) -> FactorySchedule.Progress? {
        guard let page = referencePage(kind: ReferencePage.testKind, name: type),
              page.remindEveryMonths != nil || page.remindEveryMiles != nil else { return nil }
        let rule = FactorySchedule.Rule(everyMiles: page.remindEveryMiles, everyMonths: page.remindEveryMonths)
        guard let last = tests(ofType: type).first else {
            return FactorySchedule.Progress(due: .init(), milesLeft: nil, daysLeft: 0, fraction: nil,
                                            status: .dueSoon, lastDone: nil)
        }
        return FactorySchedule.progress(for: rule, lastDone: .init(odometer: last.odometer, date: last.date),
                                        currentOdometer: currentOdometer, today: today)
    }
}

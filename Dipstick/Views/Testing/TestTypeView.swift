//
//  TestTypeView.swift
//  Dipstick
//

import SwiftUI
import SwiftData
import Charts

/// One test or inspection on one car: when it was last done, a Log button,
/// the spec and reminder (set from the manual), a chart of each reading over
/// time, every past result, and notes and photos for next time.
struct TestTypeView: View {
    let vehicle: Vehicle
    let testType: String

    @Environment(\.dismiss) private var dismiss
    @State private var isLogging = false
    @State private var editing: TestEntry?
    @State private var isEditingSettings = false

    private var template: TestTemplate.Template? { TestTemplate.template(named: testType) }
    private var page: ReferencePage? { vehicle.referencePage(kind: ReferencePage.testKind, name: testType) }

    var body: some View {
        let history = vehicle.tests(ofType: testType)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                navRow.padding(.bottom, 2)
                header(last: history.first).padding(.bottom, 6)

                Button { isLogging = true } label: {
                    Label("Log \(testType.lowercased())", systemImage: "gauge.with.dots.needle.50percent")
                }
                .buttonStyle(BigActionButtonStyle(height: 56))

                settingsPanel

                if let chart = TestChartData(history: history, template: template), chart.dates > 1 {
                    SectionTitle("Over time") {
                        Text(chart.unit)
                            .font(.dipstick(11.5, relativeTo: .caption))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 8)
                    TestChart(data: chart, specMin: page?.specMin, specMax: page?.specMax)
                        .frame(height: 200)
                        .padding(12)
                        .panel()
                }

                SectionTitle("History") {
                    Text(history.isEmpty ? "None yet" : "\(history.count) logged")
                        .font(.dipstick(11.5, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 8)
                if history.isEmpty {
                    Text("No \(testType.lowercased()) logged yet.")
                        .font(.dipstick(14, relativeTo: .subheadline))
                        .foregroundStyle(Theme.muted)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panel()
                } else {
                    PanelList(history) { entry in
                        Button { editing = entry } label: {
                            TestEntryRow(entry: entry, page: page, showsType: false)
                        }
                        .buttonStyle(.plain)
                    }
                }

                ReferenceSection(vehicle: vehicle, kind: ReferencePage.testKind, name: testType)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.ground)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $isLogging) {
            TestEntryFormView(vehicle: vehicle, testType: testType)
        }
        .fullScreenCover(item: $editing) { entry in
            TestEntryFormView(vehicle: vehicle, entry: entry)
        }
        .sheet(isPresented: $isEditingSettings) {
            TestSettingsView(vehicle: vehicle, testType: testType, unit: template?.unit ?? "")
        }
    }

    private var navRow: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(SmallControlButtonStyle())
            .accessibilityLabel("Back")
            Spacer()
        }
    }

    private func header(last: TestEntry?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                vehicle.chip
                Text(testType)
                    .font(.dipstick(22, .semibold, relativeTo: .title))
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
            }
            Text(last.map { "Last done \($0.date.formatted(.dateTime.month(.abbreviated).day().year())) at \(Units.miles($0.odometer))" }
                 ?? "Not done yet")
                .font(.dipstick(13, relativeTo: .footnote))
                .foregroundStyle(Theme.muted)
            if let reminder = vehicle.testReminder(for: testType), last != nil {
                StatusLine(status: reminder.status, text: "\(reminder.dueLabel) · \(reminder.shortSummary)")
            }
            if let template {
                Text(template.about)
                    .font(.dipstick(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 2)
            }
        }
    }

    /// Spec and reminder, tap to set from the manual.
    private var settingsPanel: some View {
        Button { isEditingSettings = true } label: {
            VStack(spacing: 0) {
                FormRow("Spec") {
                    Text(page.map(specText) ?? "Not set")
                        .font(.dipstick(14, relativeTo: .body))
                        .foregroundStyle(page?.hasSpec == true ? Theme.text : Theme.muted)
                        .multilineTextAlignment(.trailing)
                }
                FormDivider()
                FormRow("Remind every") {
                    Text(reminderText ?? "Off")
                        .font(.dipstick(14, relativeTo: .body))
                        .foregroundStyle(reminderText == nil ? Theme.muted : Theme.text)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .panel(radius: Theme.Radius.field)
        .accessibilityHint("Set the spec and reminder")
    }

    private func specText(_ page: ReferencePage) -> String {
        guard page.hasSpec else { return "Not set" }
        let unit = template?.unit ?? ""
        var parts: [String] = []
        if let min = page.specMin { parts.append("min \(TestSpec.number(min))") }
        if let max = page.specMax { parts.append("max \(TestSpec.number(max))") }
        if let spread = page.specMaxSpread { parts.append("spread ≤ \(TestSpec.number(spread))") }
        return parts.joined(separator: ", ") + (unit.isEmpty ? "" : " \(unit)")
    }

    private var reminderText: String? {
        FactorySchedule.Rule.phrase(miles: page?.remindEveryMiles, months: page?.remindEveryMonths)
    }
}

// MARK: - Chart

/// Each reading's values over time, one series per label (cylinder, wheel).
struct TestChartData {
    struct Point: Identifiable {
        let date: Date
        let label: String
        let value: Double
        var id: String { "\(label)|\(date.timeIntervalSince1970)" }
    }

    let points: [Point]
    let labels: [String]
    let unit: String
    let dates: Int

    /// nil if there's nothing numeric to chart, or readings use mixed units.
    init?(history: [TestEntry], template: TestTemplate.Template?) {
        var points: [Point] = []
        var labels: [String] = []
        var units = Set<String>()
        for entry in history.reversed() {
            for reading in entry.sortedReadings {
                guard let value = reading.value else { continue }
                points.append(Point(date: entry.date, label: reading.label, value: value))
                units.insert(reading.unit)
                if !labels.contains(reading.label) { labels.append(reading.label) }
            }
        }
        guard !points.isEmpty, units.count == 1, labels.count <= Theme.series.count else { return nil }
        self.points = points
        // Template order (Cylinder 1, 2…) where known.
        let order = template?.labels(cylinders: 12) ?? []
        self.labels = labels.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }
        self.unit = units.first ?? ""
        self.dates = Set(points.map(\.date)).count
    }
}

/// Lines per reading over time, in the series colors (fixed order by label),
/// with the spec's limits as dashed rules and a legend naming each line.
struct TestChart: View {
    let data: TestChartData
    let specMin: Double?
    let specMax: Double?

    var body: some View {
        Chart {
            ForEach(data.points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Reading", point.label))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(by: .value("Reading", point.label))
                    .symbolSize(40)
            }
            if let specMin {
                RuleMark(y: .value("Min", specMin))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.muted)
                    .annotation(position: .bottom, alignment: .leading, spacing: 2) {
                        Text("MIN \(TestSpec.number(specMin))")
                            .font(.readout(10, relativeTo: .caption2))
                            .foregroundStyle(Theme.muted)
                    }
            }
            if let specMax {
                RuleMark(y: .value("Max", specMax))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.muted)
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("MAX \(TestSpec.number(specMax))")
                            .font(.readout(10, relativeTo: .caption2))
                            .foregroundStyle(Theme.muted)
                    }
            }
        }
        .chartForegroundStyleScale(domain: data.labels, range: Array(Theme.series.prefix(data.labels.count)))
        .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(Theme.divider)
                AxisValueLabel().font(.readout(10, relativeTo: .caption2)).foregroundStyle(Theme.muted)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                    .font(.dipstick(10, relativeTo: .caption2))
                    .foregroundStyle(Theme.muted)
            }
        }
        .accessibilityLabel("Readings over time")
    }
}

// MARK: - Settings

/// The spec from the manual and how often to do the test.
struct TestSettingsView: View {
    let vehicle: Vehicle
    let testType: String
    let unit: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var specMin = ""
    @State private var specMax = ""
    @State private var spread = ""
    @State private var months = ""
    @State private var miles = ""
    @FocusState private var minFocused: Bool
    @FocusState private var maxFocused: Bool
    @FocusState private var spreadFocused: Bool
    @FocusState private var monthsFocused: Bool
    @FocusState private var milesFocused: Bool

    private func decimal(_ text: String) -> Double?? {
        let t = text.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? .some(nil) : Units.parseDecimal(t).map { .some($0) }
    }

    private func whole(_ text: String) -> Int?? {
        let t = text.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? .some(nil) : Units.parseWholeNumber(t).flatMap { $0 > 0 ? .some($0) : nil }
    }

    private var isValid: Bool {
        decimal(specMin) != nil && decimal(specMax) != nil && decimal(spread) != nil
            && whole(months) != nil && whole(miles) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                FormHeader(title: testType, vehicle: vehicle) { dismiss() }
                    .padding(.bottom, 6)

                SectionTitle("Spec") {
                    Text("From your manual · blank to skip")
                        .font(.dipstick(11.5, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
                TileRow {
                    NumberTileField(label: "Minimum", text: $specMin, placeholder: "—", unit: unit,
                                    size: 22, height: 66, focus: $minFocused)
                    NumberTileField(label: "Maximum", text: $specMax, placeholder: "—", unit: unit,
                                    size: 22, height: 66, focus: $maxFocused)
                }
                NumberTileField(label: "Most difference between readings", text: $spread, placeholder: "—",
                                unit: unit, size: 22, height: 66, focus: $spreadFocused)

                SectionTitle("Remind every") {
                    Text("Blank for no reminder")
                        .font(.dipstick(11.5, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 8)
                TileRow {
                    NumberTileField(label: "Months", text: $months, placeholder: "—", unit: "months",
                                    keyboard: .numberPad, size: 22, height: 66, focus: $monthsFocused)
                    NumberTileField(label: "Or miles", text: $miles, placeholder: "—", unit: "mi",
                                    keyboard: .numberPad, size: 22, height: 66, focus: $milesFocused)
                }
                if !isValid {
                    StatusLine(status: .overdue, text: "Check the numbers")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.ground)
        .safeAreaInset(edge: .bottom) {
            FormSaveBar(title: "Save", isEnabled: isValid,
                        isKeyboardUp: minFocused || maxFocused || spreadFocused || monthsFocused || milesFocused,
                        onHideKeyboard: {
                            minFocused = false; maxFocused = false; spreadFocused = false
                            monthsFocused = false; milesFocused = false
                        },
                        onSave: save)
        }
        .tint(Theme.accent)
        .onAppear {
            let page = vehicle.referencePage(kind: ReferencePage.testKind, name: testType)
            specMin = page?.specMin.map(TestSpec.number) ?? ""
            specMax = page?.specMax.map(TestSpec.number) ?? ""
            spread = page?.specMaxSpread.map(TestSpec.number) ?? ""
            months = page?.remindEveryMonths.map(String.init) ?? ""
            miles = page?.remindEveryMiles.map(String.init) ?? ""
        }
    }

    private func save() {
        guard let min = decimal(specMin), let max = decimal(specMax), let spread = decimal(spread),
              let months = whole(months), let miles = whole(miles) else { return }
        let page = vehicle.referencePageCreating(kind: ReferencePage.testKind, name: testType, in: modelContext)
        page.specMin = min
        page.specMax = max
        page.specMaxSpread = spread
        page.remindEveryMonths = months
        page.remindEveryMiles = miles
        modelContext.saveNow()
        dismiss()
    }
}

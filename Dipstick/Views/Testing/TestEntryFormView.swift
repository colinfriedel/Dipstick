//
//  TestEntryFormView.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Log or edit a test or inspection: its type (typed, or picked from the
/// built-in and used ones), date and odometer, its readings (a built-in
/// test's rows, plus any of your own), and notes. Readings outside the spec
/// on the test's reference page are flagged as you type.
struct TestEntryFormView: View {
    let vehicle: Vehicle
    let entry: TestEntry?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allTests: [TestEntry]

    @State private var testType: String
    @State private var date: Date
    @State private var odometer: String
    @State private var cylinders: Int
    @State private var readings: [ReadingDraft]
    @State private var notes: String
    @State private var isPickingDate = false
    @State private var isConfirmingDelete = false
    /// The template the rows were last built from, so typing doesn't wipe
    /// readings already entered for the same test.
    @State private var builtFrom: String?

    @FocusState private var typeFocused: Bool
    @FocusState private var odometerFocused: Bool
    @FocusState private var focusedReading: ReadingField?
    @FocusState private var notesFocused: Bool

    struct ReadingDraft: Identifiable {
        let id = UUID()
        var label: String
        var value = ""
        var second = ""
        var unit: String
        /// Added by hand (label and unit editable), not from the template.
        var isCustom = false
    }

    enum ReadingField: Hashable { case label(UUID), value(UUID), second(UUID), unit(UUID) }

    /// - Parameter testType: preselects the test (from its page).
    init(vehicle: Vehicle, entry: TestEntry? = nil, testType: String? = nil) {
        self.vehicle = vehicle
        self.entry = entry
        let type = entry?.testType ?? testType ?? ""
        _testType = State(initialValue: type)
        _date = State(initialValue: entry?.date ?? Date())
        _odometer = State(initialValue: entry.map { String($0.odometer) } ?? "")
        _notes = State(initialValue: entry?.notes ?? "")

        let template = TestTemplate.template(named: type)
        let previous = vehicle.tests(ofType: type).first
        let lastCylinders = previous?.sortedReadings.filter { $0.label.hasPrefix("Cylinder ") }.count ?? 0
        _cylinders = State(initialValue: lastCylinders > 0 ? lastCylinders : 4)

        if let entry {
            let templateLabels = Set(template?.labels(cylinders: 12) ?? [])
            _readings = State(initialValue: entry.sortedReadings.map {
                ReadingDraft(label: $0.label,
                             value: $0.value.map(TestSpec.number) ?? $0.text ?? "",
                             second: $0.secondValue.map(TestSpec.number) ?? "",
                             unit: $0.unit, isCustom: !templateLabels.contains($0.label))
            })
            _builtFrom = State(initialValue: template?.name)
        } else if let template {
            _readings = State(initialValue: template.labels(cylinders: lastCylinders > 0 ? lastCylinders : 4)
                .map { ReadingDraft(label: $0, unit: template.unit) })
            _builtFrom = State(initialValue: template.name)
        } else {
            _readings = State(initialValue: [])
        }
    }

    private var isEditing: Bool { entry != nil }
    private var trimmedType: String { testType.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var template: TestTemplate.Template? { TestTemplate.template(named: trimmedType) }
    private var page: ReferencePage? { vehicle.referencePage(kind: ReferencePage.testKind, name: trimmedType) }

    private var parsedOdometer: Int? {
        Units.parseWholeNumber(odometer).flatMap { $0 >= 0 ? $0 : nil }
    }

    private var canSave: Bool { !trimmedType.isEmpty && parsedOdometer != nil }

    private var isKeyboardUp: Bool {
        typeFocused || odometerFocused || focusedReading != nil || notesFocused
    }

    /// Spec problems for the template's rows (custom rows aren't checked).
    private var problems: [UUID: String] {
        guard let page, page.hasSpec else { return [:] }
        let checked = readings.filter { !$0.isCustom }
        let spec = TestSpec.Spec(min: page.specMin, max: page.specMax, maxSpread: page.specMaxSpread)
        let found = TestSpec.problems(checked.map { Units.parseDecimal($0.value) }, spec: spec)
        return Dictionary(uniqueKeysWithValues: found.map { (checked[$0.key].id, $0.value) })
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                FormHeader(title: isEditing ? "Edit test" : "Log test", vehicle: vehicle) { dismiss() }
                    .padding(.bottom, 6)

                SmallCapsLabel("Test or inspection")
                typeField
                if !isEditing { typeChips }
                if let template {
                    Text(template.about)
                        .font(.dipstick(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }

                OdometerField(text: $odometer, focus: $odometerFocused, size: 24)
                    .padding(.top, 4)
                dateRow

                SectionTitle("Readings") {
                    if let page, page.hasSpec {
                        Text(specText(page))
                            .font(.dipstick(11.5, relativeTo: .caption))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.top, 6)
                if template?.perCylinder == true { cylinderStepper }
                readingsPanel

                notesField

                if isEditing {
                    Button("Delete test", role: .destructive) { isConfirmingDelete = true }
                        .font(.dipstick(14, .semibold, relativeTo: .body))
                        .foregroundStyle(Theme.red)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.ground)
        .safeAreaInset(edge: .bottom) {
            FormSaveBar(title: isEditing ? "Save test" : "Save test", isEnabled: canSave,
                        isKeyboardUp: isKeyboardUp, onHideKeyboard: hideKeyboard, onSave: save)
        }
        .tint(Theme.accent)
        .confirmationDialog("Delete this test?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Test", role: .destructive) {
                if let entry { modelContext.delete(entry) }
                modelContext.saveNow()
                dismiss()
            }
        }
        .onChange(of: testType) { rebuildRows() }
        .onChange(of: cylinders) { rebuildRows(force: true) }
        .task {
            guard !isEditing else { return }
            await focusAfterPresentation {
                if trimmedType.isEmpty { typeFocused = true } else { odometerFocused = true }
            }
        }
    }

    private var typeField: some View {
        TextField("Test", text: $testType, prompt: Text("What did you test?").foregroundStyle(Theme.faint))
            .font(.dipstick(16, relativeTo: .body))
            .foregroundStyle(Theme.text)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.next)
            .onSubmit { odometerFocused = true }
            .focused($typeFocused)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .panel(radius: Theme.Radius.field, border: typeFocused ? Theme.accent : Theme.panelBorder,
                   lineWidth: typeFocused ? 1.5 : 1)
    }

    /// Built-in and used tests, narrowed as you type; a tap fills the name.
    private var typeChips: some View {
        let all = TestTemplate.options(addingUsed: allTests.map(\.testType))
        let shown = trimmedType.isEmpty ? all : all.filter { $0.localizedStandardContains(trimmedType) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shown, id: \.self) { option in
                    ChipButton(title: option, isSelected: option.caseInsensitiveCompare(trimmedType) == .orderedSame) {
                        testType = option
                        typeFocused = false
                        odometerFocused = true
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
    }

    private var dateRow: some View {
        VStack(spacing: 0) {
            Button { withAnimation { isPickingDate.toggle() } } label: {
                FormRow("Date") {
                    Text(Calendar.current.isDateInToday(date)
                         ? "Today, \(date.formatted(.dateTime.month(.abbreviated).day()))"
                         : date.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.dipstick(15, .semibold, relativeTo: .body))
                        .foregroundStyle(Theme.text)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isPickingDate {
                DatePicker("Date", selection: $date, in: ...Date.now.addingTimeInterval(86_400),
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(8)
            }
        }
        .panel(radius: Theme.Radius.field)
    }

    private var cylinderStepper: some View {
        FormRow("Cylinders") {
            Stepper(value: $cylinders, in: 1...12) {
                Text("\(cylinders)")
                    .font(.readout(17, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .fixedSize()
        }
        .panel(radius: Theme.Radius.field)
    }

    private var readingsPanel: some View {
        VStack(spacing: 0) {
            if let second = template?.secondLabel, readings.contains(where: { !$0.isCustom }) {
                HStack {
                    Spacer()
                    SmallCapsLabel(template?.unit ?? "").frame(width: 76, alignment: .trailing)
                    SmallCapsLabel(second).frame(width: 76, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
            }
            ForEach($readings) { $reading in
                ReadingRow(reading: $reading, focused: $focusedReading,
                           showsSecond: template?.secondLabel != nil && !reading.isCustom,
                           problem: problems[reading.id]) {
                    readings.removeAll { $0.id == reading.id }
                }
                FormDivider()
            }
            Button {
                let draft = ReadingDraft(label: "", unit: template?.unit ?? "", isCustom: true)
                readings.append(draft)
                focusedReading = .label(draft.id)
            } label: {
                Label("Add reading", systemImage: "plus")
                    .font(.dipstick(14, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .panel(radius: Theme.Radius.field)
    }

    private var notesField: some View {
        TextField("Notes", text: $notes,
                  prompt: Text("Notes (conditions, what you noticed)").foregroundStyle(Theme.faint), axis: .vertical)
            .font(.dipstick(15, relativeTo: .body))
            .foregroundStyle(Theme.text)
            .lineLimit(2...)
            .focused($notesFocused)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            .panel(radius: Theme.Radius.field)
            .padding(.top, 6)
    }

    private func specText(_ page: ReferencePage) -> String {
        let unit = template?.unit ?? ""
        var parts: [String] = []
        if let min = page.specMin { parts.append("min \(TestSpec.number(min))") }
        if let max = page.specMax { parts.append("max \(TestSpec.number(max))") }
        if let spread = page.specMaxSpread { parts.append("spread ≤ \(TestSpec.number(spread))") }
        return "Spec: " + parts.joined(separator: ", ") + (unit.isEmpty ? "" : " \(unit)")
    }

    // MARK: Rows

    /// Rows follow the chosen test: a built-in test's rows (keeping custom
    /// rows and any values already typed for the same labels).
    private func rebuildRows(force: Bool = false) {
        guard !isEditing || force else { return }
        guard let template else {
            builtFrom = nil
            return
        }
        guard force || builtFrom != template.name else { return }
        let typed = Dictionary(readings.filter { !$0.isCustom }.map { ($0.label, $0) }, uniquingKeysWith: { a, _ in a })
        let rows = template.labels(cylinders: cylinders).map { label in
            var row = ReadingDraft(label: label, unit: template.unit)
            if let old = typed[label] { row.value = old.value; row.second = old.second }
            return row
        }
        readings = rows + readings.filter(\.isCustom)
        builtFrom = template.name
    }

    private func hideKeyboard() {
        typeFocused = false
        odometerFocused = false
        focusedReading = nil
        notesFocused = false
    }

    // MARK: Saving

    private func save() {
        guard canSave, let odometerValue = parsedOdometer else { return }
        let target = entry ?? TestEntry(odometer: odometerValue, testType: trimmedType)
        target.date = date
        target.odometer = odometerValue
        target.testType = trimmedType
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        target.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        if entry == nil {
            modelContext.insert(target)
            target.vehicle = vehicle
        }

        for old in target.readings ?? [] { modelContext.delete(old) }
        var order = 0
        for draft in readings {
            let label = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let valueText = draft.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = Units.parseDecimal(valueText)
            let second = Units.parseDecimal(draft.second)
            guard !valueText.isEmpty || second != nil else { continue }  // left blank
            let reading = TestReading(label: label.isEmpty ? "Reading" : label, value: value, secondValue: second,
                                      unit: draft.unit.trimmingCharacters(in: .whitespacesAndNewlines),
                                      text: value == nil ? valueText : nil, order: order)
            modelContext.insert(reading)
            reading.entry = target
            order += 1
        }
        vehicle.recordOdometer(odometerValue)
        modelContext.saveNow()
        dismiss()
    }
}

/// One reading: its label, value (a number, or words like "Cracked"),
/// optional second value, and unit. Custom rows can edit the label and unit.
private struct ReadingRow: View {
    @Binding var reading: TestEntryFormView.ReadingDraft
    var focused: FocusState<TestEntryFormView.ReadingField?>.Binding
    let showsSecond: Bool
    let problem: String?
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if reading.isCustom {
                    TextField("Label", text: $reading.label, prompt: Text("Reading").foregroundStyle(Theme.faint))
                        .font(.dipstick(15, .semibold, relativeTo: .body))
                        .foregroundStyle(Theme.text)
                        .focused(focused, equals: .label(reading.id))
                } else {
                    Text(reading.label)
                        .font(.dipstick(15, .semibold, relativeTo: .body))
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 4)
                }
                valueField($reading.value, placeholder: reading.unit.isEmpty ? "—" : reading.unit, field: .value(reading.id))
                if showsSecond {
                    valueField($reading.second, placeholder: "—", field: .second(reading.id))
                }
                if reading.isCustom {
                    TextField("Unit", text: $reading.unit, prompt: Text("unit").foregroundStyle(Theme.faint))
                        .font(.dipstick(13, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 48)
                        .focused(focused, equals: .unit(reading.id))
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 32, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove reading")
                }
            }
            if let problem {
                StatusLine(status: .overdue, text: "Out of spec: \(problem)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 52)
    }

    private func valueField(_ text: Binding<String>, placeholder: String,
                            field: TestEntryFormView.ReadingField) -> some View {
        TextField(placeholder, text: text, prompt: Text(placeholder).foregroundStyle(Theme.faint))
            .font(.readout(17, relativeTo: .body))
            .foregroundStyle(problem == nil ? Theme.text : Theme.red)
            .multilineTextAlignment(.trailing)
            .keyboardType(reading.isCustom ? .default : .decimalPad)
            .frame(width: 76)
            .focused(focused, equals: field)
    }
}

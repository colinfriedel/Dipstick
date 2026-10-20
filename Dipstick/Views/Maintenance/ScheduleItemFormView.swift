//
//  ScheduleItemFormView.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Add or edit one factory schedule item: what the manual calls it, which
/// logged service counts as doing it, how often the manual says, and your own
/// interval if you'd rather do it more (or less) often.
struct ScheduleItemFormView: View {
    let vehicle: Vehicle
    let item: ScheduleItem?
    /// Called just before the item is deleted.
    var onRemove: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [MaintenanceEntry]

    @State private var name: String
    @State private var serviceType: String
    @State private var everyMiles: String
    @State private var everyMonths: String
    @State private var firstMiles: String
    @State private var firstMonths: String
    @State private var customMiles: String
    @State private var customMonths: String
    @State private var note: String
    @State private var isConfirmingDelete = false

    @FocusState private var focused: Field?
    @FocusState private var everyMilesFocused: Bool
    @FocusState private var everyMonthsFocused: Bool
    @FocusState private var firstMilesFocused: Bool
    @FocusState private var firstMonthsFocused: Bool
    @FocusState private var customMilesFocused: Bool
    @FocusState private var customMonthsFocused: Bool

    private enum Field: Hashable { case name, serviceType, note }

    init(vehicle: Vehicle, item: ScheduleItem? = nil, onRemove: (() -> Void)? = nil) {
        self.vehicle = vehicle
        self.item = item
        self.onRemove = onRemove
        _customMiles = State(initialValue: item?.customEveryMiles.map(String.init) ?? "")
        _customMonths = State(initialValue: item?.customEveryMonths.map(String.init) ?? "")
        _name = State(initialValue: item?.name ?? "")
        _serviceType = State(initialValue: item?.serviceType ?? "")
        _everyMiles = State(initialValue: item?.everyMiles.map(String.init) ?? "")
        _everyMonths = State(initialValue: item?.everyMonths.map(String.init) ?? "")
        _firstMiles = State(initialValue: item?.firstMiles.map(String.init) ?? "")
        _firstMonths = State(initialValue: item?.firstMonths.map(String.init) ?? "")
        _note = State(initialValue: item?.note ?? "")
    }

    private var isEditing: Bool { item != nil }

    /// Built-in names plus every service type logged on any car.
    private var serviceOptions: [String] {
        ServiceType.options(addingUsed: allEntries.map(\.serviceType))
    }

    // MARK: Validation

    /// A blank field is nil; anything else must be a positive whole number.
    private func number(_ text: String) -> Int?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        return Units.parseWholeNumber(trimmed).flatMap { $0 > 0 ? .some($0) : nil }
    }

    private var rule: FactorySchedule.Rule? {
        guard let everyMiles = number(everyMiles), let everyMonths = number(everyMonths),
              let firstMiles = number(firstMiles), let firstMonths = number(firstMonths) else { return nil }
        return .init(everyMiles: everyMiles, everyMonths: everyMonths,
                     firstMiles: firstMiles, firstMonths: firstMonths)
    }

    private var custom: (miles: Int?, months: Int?)? {
        guard let miles = number(customMiles), let months = number(customMonths) else { return nil }
        return (miles, months)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedType: String { serviceType.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool { !trimmedName.isEmpty && !trimmedType.isEmpty && rule != nil && custom != nil }

    private var isKeyboardUp: Bool {
        focused != nil || everyMilesFocused || everyMonthsFocused || firstMilesFocused || firstMonthsFocused
            || customMilesFocused || customMonthsFocused
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                FormHeader(title: isEditing ? "Edit item" : "Add item", vehicle: vehicle) { dismiss() }
                    .padding(.bottom, 6)

                textField("Name", text: $name, prompt: "Replace engine oil", field: .name)

                SmallCapsLabel("Counts when you log").padding(.top, 6)
                serviceChips
                textField("Service", text: $serviceType, prompt: "Oil change", field: .serviceType)

                SectionTitle("Your interval") {
                    if custom.map({ $0.miles != nil || $0.months != nil }) ?? true {
                        Button("Use factory") { customMiles = ""; customMonths = "" }
                            .font(.dipstick(11.5, .semibold, relativeTo: .caption))
                            .foregroundStyle(Theme.accentText)
                    } else {
                        Text("Blank follows the factory")
                            .font(.dipstick(11.5, relativeTo: .caption))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .padding(.top, 6)
                intervalPanel(miles: $customMiles, months: $customMonths,
                              milesFocus: $customMilesFocused, monthsFocus: $customMonthsFocused,
                              milesPlaceholder: everyMiles.isEmpty ? "—" : everyMiles,
                              monthsPlaceholder: everyMonths.isEmpty ? "—" : everyMonths)

                SectionTitle("Factory: every") {
                    Text("Whichever comes first")
                        .font(.dipstick(11.5, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 6)
                intervalPanel(miles: $everyMiles, months: $everyMonths,
                              milesFocus: $everyMilesFocused, monthsFocus: $everyMonthsFocused)

                SectionTitle("Factory: first time") {
                    Text("Optional, if the first one differs")
                        .font(.dipstick(11.5, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 6)
                intervalPanel(miles: $firstMiles, months: $firstMonths,
                              milesFocus: $firstMilesFocused, monthsFocus: $firstMonthsFocused)

                if rule == nil || custom == nil {
                    StatusLine(status: .overdue, text: "Use whole numbers for the intervals")
                        .padding(.horizontal, 6)
                } else if let summary = effectiveRule?.summary {
                    StatusLine(status: .ok, text: summary).padding(.horizontal, 6)
                }

                textField("Note", text: $note, prompt: "Optional", field: .note)
                    .padding(.top, 6)

                if isEditing {
                    Button("Remove from schedule", role: .destructive) { isConfirmingDelete = true }
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
            FormSaveBar(title: isEditing ? "Save item" : "Add item", isEnabled: canSave,
                        isKeyboardUp: isKeyboardUp, onHideKeyboard: hideKeyboard, onSave: save)
        }
        .tint(Theme.accent)
        .confirmationDialog("Remove \(trimmedName.isEmpty ? "this item" : trimmedName)?",
                            isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                onRemove?()
                if let item { modelContext.delete(item) }
                modelContext.saveNow()
                dismiss()
            }
        }
        .task {
            if !isEditing { await focusAfterPresentation { focused = .name } }
        }
    }

    private func textField(_ label: String, text: Binding<String>, prompt: String, field: Field) -> some View {
        HStack(alignment: .center, spacing: 12) {
            SmallCapsLabel(label)
            TextField(label, text: text, prompt: Text(prompt).foregroundStyle(Theme.faint), axis: .vertical)
                .font(.dipstick(15, relativeTo: .body))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.sentences)
                .focused($focused, equals: field)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 52)
        .panel(radius: Theme.Radius.field)
    }

    private var serviceChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(serviceOptions, id: \.self) { option in
                        ChipButton(title: option,
                                   isSelected: option.caseInsensitiveCompare(trimmedType) == .orderedSame) {
                            serviceType = option
                        }
                        .id(option)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollClipDisabled()
            .onAppear {
                if let match = serviceOptions.first(where: { $0.caseInsensitiveCompare(trimmedType) == .orderedSame }) {
                    proxy.scrollTo(match, anchor: .center)
                }
            }
        }
    }

    /// The rule the chart will use, as the fields stand.
    private var effectiveRule: FactorySchedule.Rule? {
        guard var rule, let custom else { return nil }
        if let miles = custom.miles { rule.everyMiles = miles }
        if let months = custom.months { rule.everyMonths = months }
        return rule
    }

    private func intervalPanel(miles: Binding<String>, months: Binding<String>,
                               milesFocus: FocusState<Bool>.Binding,
                               monthsFocus: FocusState<Bool>.Binding,
                               milesPlaceholder: String = "—",
                               monthsPlaceholder: String = "—") -> some View {
        TileRow {
            NumberTileField(label: "Miles", text: miles, placeholder: milesPlaceholder, unit: "mi",
                            keyboard: .numberPad, size: 22, height: 66, focus: milesFocus)
            NumberTileField(label: "Or months", text: months, placeholder: monthsPlaceholder, unit: "months",
                            keyboard: .numberPad, size: 22, height: 66, focus: monthsFocus)
        }
    }

    private func hideKeyboard() {
        focused = nil
        everyMilesFocused = false
        everyMonthsFocused = false
        firstMilesFocused = false
        firstMonthsFocused = false
        customMilesFocused = false
        customMonthsFocused = false
    }

    private func save() {
        guard canSave, let rule, let custom else { return }
        let target: ScheduleItem
        if let item {
            target = item
        } else {
            let order = (vehicle.scheduleItems ?? []).map(\.order).max().map { $0 + 1 } ?? 0
            target = ScheduleItem(name: trimmedName, serviceType: trimmedType, order: order)
            modelContext.insert(target)
            target.vehicle = vehicle
        }
        target.name = trimmedName
        target.serviceType = trimmedType
        target.rule = rule
        target.customEveryMiles = custom.miles
        target.customEveryMonths = custom.months
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        target.note = trimmedNote.isEmpty ? nil : trimmedNote
        modelContext.saveNow()
        dismiss()
    }
}

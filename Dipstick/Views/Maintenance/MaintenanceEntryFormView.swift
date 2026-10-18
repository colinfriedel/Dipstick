//
//  MaintenanceEntryFormView.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Log or edit a service (design board J). Works for DIY jobs (the total adds
/// up the parts) and shop visits (type the bill's total). For a new service
/// the odometer starts empty: enter what the car shows.
struct MaintenanceEntryFormView: View {
    let vehicle: Vehicle
    let entry: MaintenanceEntry?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Every logged service, so custom service names show up as options.
    @Query private var allEntries: [MaintenanceEntry]

    @State private var serviceChoice: String
    @State private var customService: String
    @State private var date: Date
    @State private var odometer: String
    @State private var parts: [PartDraft]
    /// A total typed by hand; nil means "use the parts total".
    @State private var manualCost: String?
    @State private var everyMiles: String
    @State private var everyMonths: String
    @State private var lastPrefill = MaintenanceSchedule.Interval()
    @State private var notes: String
    @State private var isPickingDate = false

    @FocusState private var odometerFocused: Bool
    @FocusState private var costFocused: Bool
    @FocusState private var milesFocused: Bool
    @FocusState private var monthsFocused: Bool
    @FocusState private var focusedPart: PartField?

    private static let customChoice = "Custom…"

    struct PartDraft: Identifiable {
        let id = UUID()
        var name: String = ""
        var partNumber: String = ""
        var quantity: Int = 1
        /// Price of one.
        var cost: String = ""
        /// True when `cost` was worked out from the total cost rather than
        /// typed, so it follows the total and quantity until typed over.
        var costIsDerived = false

        var lineTotal: Double { (Units.parseDecimal(cost) ?? 0) * Double(quantity) }
    }

    enum PartField: Hashable {
        case name(UUID), number(UUID), cost(UUID)
    }

    /// - Parameter serviceType: preselects the service when logging a new one
    ///   (e.g. from a service lamp on Home).
    init(vehicle: Vehicle, entry: MaintenanceEntry? = nil, serviceType: String? = nil) {
        self.vehicle = vehicle
        self.entry = entry

        _serviceChoice = State(initialValue: entry?.serviceType ?? serviceType ?? ServiceType.builtIn[0])
        _customService = State(initialValue: "")
        _date = State(initialValue: entry?.date ?? Date())
        _odometer = State(initialValue: entry.map { String($0.odometer) } ?? "")
        _notes = State(initialValue: entry?.notes ?? "")

        let existingParts = entry?.sortedParts ?? []
        _parts = State(initialValue: existingParts.map {
            PartDraft(name: $0.name, partNumber: $0.partNumber ?? "", quantity: max($0.quantity, 1),
                      cost: $0.cost > 0 ? Self.money($0.cost) : "")
        })
        let partsSum = existingParts.reduce(0) { $0 + $1.lineTotal }
        if let entry, abs(entry.cost - partsSum) > 0.005 {
            _manualCost = State(initialValue: Self.money(entry.cost))
        } else {
            _manualCost = State(initialValue: nil)
        }

        let interval = entry.map {
            MaintenanceSchedule.interval(odometer: $0.odometer, date: $0.date, due: $0.due)
        } ?? .init()
        _everyMiles = State(initialValue: interval.miles.map(String.init) ?? "")
        _everyMonths = State(initialValue: interval.months.map(String.init) ?? "")
    }

    private var isEditing: Bool { entry != nil }

    // MARK: Service type

    /// This car's services first (most recent first), then the rest of the
    /// built-in and custom names, then Custom….
    private var serviceOptions: [String] {
        var seen = Set<String>()
        let mine = (vehicle.maintenanceEntries ?? []).sorted { $0.date > $1.date }.map(\.serviceType)
        let all = mine + ServiceType.options(addingUsed: allEntries.map(\.serviceType))
        var options = all.filter { seen.insert($0.lowercased()).inserted }
        if !options.contains(where: { $0.caseInsensitiveCompare(serviceChoice) == .orderedSame }),
           serviceChoice != Self.customChoice {
            options.insert(serviceChoice, at: 0)
        }
        return options + [Self.customChoice]
    }

    private var resolvedServiceType: String {
        serviceChoice == Self.customChoice
            ? customService.trimmingCharacters(in: .whitespacesAndNewlines)
            : serviceChoice
    }

    // MARK: Cost

    private var partsTotal: Double {
        parts.reduce(0) { $0 + $1.lineTotal }
    }

    private var costText: Binding<String> {
        Binding(
            get: { manualCost ?? (partsTotal > 0 ? Self.money(partsTotal) : "") },
            set: {
                manualCost = $0.isEmpty ? nil : $0
                deriveSinglePartPrice()
            }
        )
    }

    /// With exactly one part and no price typed for it, a total typed at the
    /// top fills in the part's price each (total ÷ quantity).
    private func deriveSinglePartPrice() {
        guard parts.count == 1, parts[0].cost.isEmpty || parts[0].costIsDerived else { return }
        if let manualCost, let total = Units.parseDecimal(manualCost), total > 0 {
            parts[0].cost = Self.money(total / Double(parts[0].quantity))
            parts[0].costIsDerived = true
        } else if parts[0].costIsDerived {
            parts[0].cost = ""
            parts[0].costIsDerived = false
        }
    }

    private var parsedCost: Double? {
        guard let manualCost else { return partsTotal }
        return Units.parseDecimal(manualCost).flatMap { $0 >= 0 ? $0 : nil }
    }

    // MARK: Validation

    private var parsedOdometer: Int? {
        Units.parseWholeNumber(odometer).flatMap { $0 >= 0 ? $0 : nil }
    }

    /// nil = invalid; .some(nil) = left blank.
    private func optionalPositiveInt(_ text: String) -> Int?? {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return .some(nil) }
        return Units.parseWholeNumber(text).flatMap { $0 > 0 ? .some($0) : nil }
    }

    private var interval: MaintenanceSchedule.Interval? {
        guard let miles = optionalPositiveInt(everyMiles),
              let months = optionalPositiveInt(everyMonths) else { return nil }
        return .init(miles: miles, months: months)
    }

    private var partsAreValid: Bool {
        parts.allSatisfy { $0.cost.isEmpty || (Units.parseDecimal($0.cost).map { $0 >= 0 } ?? false) }
    }

    private var canSave: Bool {
        !resolvedServiceType.isEmpty && parsedOdometer != nil && parsedCost != nil
            && interval != nil && partsAreValid
    }

    private var isKeyboardUp: Bool {
        odometerFocused || costFocused || milesFocused || monthsFocused || focusedPart != nil
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                FormHeader(title: isEditing ? "Edit service" : "Log service", vehicle: vehicle) { dismiss() }
                    .padding(.bottom, 6)

                SmallCapsLabel("Service")
                serviceChips
                if serviceChoice == Self.customChoice {
                    TextField("Service name", text: $customService,
                              prompt: Text("Service name").foregroundStyle(Theme.faint))
                        .font(.dipstick(16, relativeTo: .body))
                        .foregroundStyle(Theme.text)
                        .textInputAutocapitalization(.sentences)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .panel(radius: Theme.Radius.field)
                }

                OdometerField(text: $odometer, focus: $odometerFocused, size: 24)
                    .padding(.top, 4)

                TileRow {
                    dateTile
                    NumberTileField(label: "Total cost", text: costText, placeholder: "$0.00",
                                    prefix: "$", size: 24, focus: $costFocused)
                }
                if isPickingDate {
                    DatePicker("Date", selection: $date, in: ...Date.now.addingTimeInterval(86_400),
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(8)
                        .panel(radius: Theme.Radius.field)
                }

                SectionTitle("Parts used") {
                    Text(manualCost == nil ? "Total adds up from parts" : "Total typed in")
                        .font(.dipstick(11.5, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 6)
                partsPanel
                if manualCost != nil, partsTotal > 0, abs((parsedCost ?? 0) - partsTotal) > 0.005 {
                    Button("Parts add up to \(Units.currency(partsTotal)). Use parts total") { manualCost = nil }
                        .font(.dipstick(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }

                SectionTitle("Next due") {
                    Text("Use either or both")
                        .font(.dipstick(11.5, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 6)
                nextDuePanel

                notesField
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.ground)
        .safeAreaInset(edge: .bottom) {
            FormSaveBar(
                title: "Save service", isEnabled: canSave, isKeyboardUp: isKeyboardUp,
                onHideKeyboard: hideKeyboard, onSave: save
            )
        }
        .tint(Theme.accent)
        .onAppear { if !isEditing { prefillInterval() } }
        .onChange(of: serviceChoice) { if !isEditing { prefillInterval() } }
        .onChange(of: parts.first?.quantity) { if manualCost != nil { deriveSinglePartPrice() } }
        .task {
            if !isEditing { await focusAfterPresentation { odometerFocused = true } }
        }
    }

    private var serviceChips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(serviceOptions, id: \.self) { option in
                        ChipButton(title: option, isSelected: option == serviceChoice) {
                            serviceChoice = option
                        }
                        .id(option)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollClipDisabled()
            .onAppear { proxy.scrollTo(serviceChoice, anchor: .center) }
        }
    }

    private var dateTile: some View {
        Button { withAnimation { isPickingDate.toggle() } } label: {
            VStack(alignment: .leading) {
                SmallCapsLabel("Date")
                Spacer(minLength: 4)
                Text(Calendar.current.isDateInToday(date)
                     ? "Today, \(date.formatted(.dateTime.month(.abbreviated).day()))"
                     : date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.dipstick(16, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .panel(radius: Theme.Radius.tile,
                   border: isPickingDate ? Theme.accent : Theme.panelBorder,
                   lineWidth: isPickingDate ? 1.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var partsPanel: some View {
        VStack(spacing: 0) {
            ForEach($parts) { $part in
                PartRow(part: $part, focusedPart: $focusedPart) {
                    parts.removeAll { $0.id == part.id }
                }
                FormDivider()
            }
            Button {
                let draft = PartDraft()
                parts.append(draft)
                focusedPart = .name(draft.id)
            } label: {
                Label("Add part", systemImage: "plus")
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

    private var nextDuePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            TileRow {
                NumberTileField(label: "Every", text: $everyMiles, placeholder: "—",
                                unit: "mi", keyboard: .numberPad, size: 22, height: 66, focus: $milesFocused)
                NumberTileField(label: "Or every", text: $everyMonths, placeholder: "—",
                                unit: "months", keyboard: .numberPad, size: 22, height: 66, focus: $monthsFocused)
            }
            dueResult
        }
        .padding(10)
        .panel(radius: Theme.Radius.field)
    }

    @ViewBuilder
    private var dueResult: some View {
        if let interval {
            if !interval.isEmpty, let reading = parsedOdometer {
                let due = MaintenanceSchedule.nextDue(odometer: reading, date: date, every: interval)
                let parts = [
                    due.odometer.map { "\($0.formatted()) mi" },
                    due.date.map { $0.formatted(.dateTime.month(.abbreviated).year()) },
                ].compactMap { $0 }
                StatusLine(status: .dueSoon,
                           text: "Next at \(parts.joined(separator: " or "))\(parts.count == 2 ? ", whichever first" : "")")
                    .padding(.horizontal, 6)
            } else if !interval.isEmpty {
                Text("Enter the odometer to see when it's next due.")
                    .font(.dipstick(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6)
            }
        } else {
            StatusLine(status: .overdue, text: "Use whole numbers for the interval")
                .padding(.horizontal, 6)
        }
    }

    private var notesField: some View {
        HStack(alignment: .center) {
            SmallCapsLabel("Notes")
            TextField("Optional", text: $notes,
                      prompt: Text("Optional").foregroundStyle(Theme.faint), axis: .vertical)
                .font(.dipstick(15, relativeTo: .body))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 52)
        .panel(radius: Theme.Radius.field)
        .padding(.top, 6)
    }

    private func hideKeyboard() {
        odometerFocused = false
        costFocused = false
        milesFocused = false
        monthsFocused = false
        focusedPart = nil
    }

    // MARK: Interval prefill

    /// Offer the interval used last time for this service on this vehicle,
    /// without overwriting anything the user typed.
    private func prefillInterval() {
        let current = MaintenanceSchedule.Interval(
            miles: Units.parseWholeNumber(everyMiles),
            months: Units.parseWholeNumber(everyMonths)
        )
        guard current.isEmpty || current == lastPrefill else { return }

        let previous = (vehicle.maintenanceEntries ?? [])
            .filter { $0.serviceType.caseInsensitiveCompare(resolvedServiceType) == .orderedSame }
            .max { $0.date < $1.date }
        let suggestion = previous.map {
            MaintenanceSchedule.interval(odometer: $0.odometer, date: $0.date, due: $0.due)
        } ?? .init()

        everyMiles = suggestion.miles.map(String.init) ?? ""
        everyMonths = suggestion.months.map(String.init) ?? ""
        lastPrefill = suggestion
    }

    // MARK: Saving

    private func save() {
        guard let odometerValue = parsedOdometer,
              let costValue = parsedCost,
              let interval else { return }

        let target = entry ?? MaintenanceEntry(odometer: odometerValue, serviceType: resolvedServiceType)
        let due = MaintenanceSchedule.nextDue(odometer: odometerValue, date: date, every: interval)

        target.date = date
        target.odometer = odometerValue
        target.serviceType = resolvedServiceType
        target.cost = costValue
        target.notes = nilIfBlank(notes)
        target.nextDueOdometer = due.odometer
        target.nextDueDate = due.date

        if entry == nil {
            modelContext.insert(target)
            target.vehicle = vehicle
        }

        // Replace the parts wholesale; simpler than diffing a short list.
        for old in target.parts ?? [] {
            modelContext.delete(old)
        }
        for draft in parts {
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let partNumber = nilIfBlank(draft.partNumber)
            let cost = Units.parseDecimal(draft.cost) ?? 0
            guard !name.isEmpty || partNumber != nil || cost > 0 else { continue }
            let part = PartUsed(name: name.isEmpty ? "Part" : name, cost: cost,
                                partNumber: partNumber, quantity: draft.quantity)
            modelContext.insert(part)
            part.entry = target
        }

        vehicle.recordOdometer(odometerValue)
        modelContext.saveNow()
        dismiss()
    }

    private func nilIfBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func money(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

/// One part in the service form: name on top; part number, quantity and the
/// price of one underneath. Shows the line total once there's more than one.
private struct PartRow: View {
    @Binding var part: MaintenanceEntryFormView.PartDraft
    var focusedPart: FocusState<MaintenanceEntryFormView.PartField?>.Binding
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                TextField("Part name", text: $part.name,
                          prompt: Text("Part name").foregroundStyle(Theme.faint))
                    .font(.dipstick(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                    .focused(focusedPart, equals: .name(part.id))
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(part.name.isEmpty ? "part" : part.name)")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    numberField
                    quantityControl
                    costField.frame(width: 84)
                }
                VStack(alignment: .leading, spacing: 6) {
                    numberField
                    HStack(spacing: 10) {
                        quantityControl
                        Spacer(minLength: 0)
                        costField
                    }
                }
            }
            .padding(.trailing, 10)
            if part.quantity > 1, part.lineTotal > 0 {
                Text("\(part.quantity) × \(Units.currency(part.lineTotal / Double(part.quantity))) = \(Units.currency(part.lineTotal))")
                    .font(.readout(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 10)
                    .padding(.top, 2)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.bottom, 10)
    }

    private var numberField: some View {
        TextField("Part number", text: $part.partNumber,
                  prompt: Text("Part #").foregroundStyle(Theme.faint))
            .font(.readout(14, relativeTo: .body))
            .foregroundStyle(Theme.text)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .frame(minHeight: 36)
            .focused(focusedPart, equals: .number(part.id))
    }

    private var quantityControl: some View {
        HStack(spacing: 0) {
            stepButton("minus", label: "One fewer", enabled: part.quantity > 1) { part.quantity -= 1 }
            Text("×\(part.quantity)")
                .font(.readout(15, relativeTo: .body))
                .foregroundStyle(Theme.text)
                .monospacedDigit()
                .frame(minWidth: 30)
                .accessibilityHidden(true)
            stepButton("plus", label: "One more", enabled: part.quantity < 99) { part.quantity += 1 }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.selectedFill))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.selectedBorder, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quantity")
        .accessibilityValue("\(part.quantity)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if part.quantity < 99 { part.quantity += 1 }
            case .decrement: if part.quantity > 1 { part.quantity -= 1 }
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? Theme.text : Theme.faint)
                .frame(width: 34, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// Typing a price stops it following the total cost.
    private var typedCost: Binding<String> {
        Binding(
            get: { part.cost },
            set: { part.cost = $0; part.costIsDerived = false }
        )
    }

    private var costField: some View {
        TextField(part.quantity > 1 ? "Price each" : "Price", text: typedCost,
                  prompt: Text(part.quantity > 1 ? "$ each" : "$0.00").foregroundStyle(Theme.faint))
            .font(.readout(15, relativeTo: .body))
            .foregroundStyle(Theme.text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(minHeight: 36)
            .focused(focusedPart, equals: .cost(part.id))
    }
}

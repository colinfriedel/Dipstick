//
//  MaintenanceEntryFormView.swift
//  Dipstick
//

import SwiftUI
import SwiftData
import PhotosUI

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
    @State private var photos: [PhotoDraft]
    @State private var isChoosingPhotoSource = false
    @State private var isPickingPhotos = false
    @State private var isTakingPhoto = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var viewingPhoto: PhotoDraft?
    @State private var isChoosingReceiptSource = false
    @State private var isPickingReceipt = false
    @State private var isPhotographingReceipt = false
    @State private var pickedReceipt: PhotosPickerItem?
    @State private var receipt: ReceiptImage?

    /// A receipt photo or screenshot to review.
    struct ReceiptImage: Identifiable {
        let id = UUID()
        let data: Data
    }

    @FocusState private var odometerFocused: Bool
    @FocusState private var serviceNameFocused: Bool
    @FocusState private var costFocused: Bool
    @FocusState private var milesFocused: Bool
    @FocusState private var monthsFocused: Bool
    @FocusState private var focusedPart: PartField?
    @FocusState private var notesFocused: Bool

    private static let customChoice = "Custom…"

    /// Opened from plain LOG SERVICE (no service picked for you): you type
    /// the service, and the chips under the field fill it in.
    private let startsTyped: Bool

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

        startsTyped = entry == nil && serviceType == nil
        _serviceChoice = State(initialValue: entry?.serviceType ?? serviceType ?? Self.customChoice)
        _customService = State(initialValue: "")
        _date = State(initialValue: entry?.date ?? Date())
        _odometer = State(initialValue: entry.map { String($0.odometer) } ?? "")
        _notes = State(initialValue: entry?.notes ?? "")
        _photos = State(initialValue: (entry?.sortedPhotos ?? []).map {
            PhotoDraft(data: $0.data, caption: $0.caption, existing: $0)
        })

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
    /// built-in, scheduled and custom names, then Custom….
    private var serviceOptions: [String] {
        var seen = Set<String>()
        let mine = (vehicle.maintenanceEntries ?? []).sorted { $0.date > $1.date }.map(\.serviceType)
        let scheduled = vehicle.sortedScheduleItems.map(\.serviceType)
        let all = mine + ServiceType.options(addingUsed: allEntries.map(\.serviceType) + scheduled)
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
        odometerFocused || serviceNameFocused || costFocused || milesFocused || monthsFocused
            || focusedPart != nil || notesFocused
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                FormHeader(title: isEditing ? "Edit service" : "Log service", vehicle: vehicle) { dismiss() }
                    .padding(.bottom, 6)

                SmallCapsLabel("Service")
                if startsTyped {
                    serviceNameField
                    suggestionChips
                } else {
                    serviceChips
                    if serviceChoice == Self.customChoice { serviceNameField }
                }
                if !resolvedServiceType.isEmpty,
                   vehicle.hasPastServiceNotes(ofType: resolvedServiceType, excluding: entry) {
                    SectionTitle("From past services") {
                        Text("Notes and photos")
                            .font(.dipstick(11.5, relativeTo: .caption))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 6)
                    PastServiceNotes(vehicle: vehicle, serviceType: resolvedServiceType, excluding: entry)
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
                if manualCost != nil, partsTotal > 0, let cost = parsedCost, abs(cost - partsTotal) > 0.005 {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(cost > partsTotal
                             ? "Parts \(Units.currency(partsTotal)) + \(Units.currency(cost - partsTotal)) tax and fees"
                             : "Parts add up to \(Units.currency(partsTotal))")
                            .foregroundStyle(Theme.muted)
                        Spacer(minLength: 4)
                        Button("Use parts total") { manualCost = nil }
                            .foregroundStyle(Theme.accentText)
                    }
                    .font(.dipstick(12, relativeTo: .caption))
                }

                SectionTitle("Next due") {
                    Text("Use either or both")
                        .font(.dipstick(11.5, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 6)
                nextDuePanel

                notesSection
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
        .confirmationDialog("Add parts from a receipt", isPresented: $isChoosingReceiptSource) {
            Button("Take Photo") { isPhotographingReceipt = true }
            Button("Choose Photo or Screenshot") { isPickingReceipt = true }
        }
        .photosPicker(isPresented: $isPickingReceipt, selection: $pickedReceipt, matching: .images)
        .onChange(of: pickedReceipt) {
            guard let item = pickedReceipt else { return }
            pickedReceipt = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                // Let the picker finish closing first.
                try? await Task.sleep(for: .milliseconds(400))
                receipt = ReceiptImage(data: data)
            }
        }
        .fullScreenCover(isPresented: $isPhotographingReceipt) {
            CameraPicker { data in
                isPhotographingReceipt = false
                if let data {
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        receipt = ReceiptImage(data: data)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $receipt) { image in
            ReceiptReviewView(imageData: image.data) { found, keepPhoto in
                addFromReceipt(found, keepPhoto: keepPhoto)
            }
        }
        .confirmationDialog("Add photos", isPresented: $isChoosingPhotoSource) {
            Button("Take Photo") { isTakingPhoto = true }
            Button("Choose Photos") { isPickingPhotos = true }
        }
        .photosPicker(isPresented: $isPickingPhotos, selection: $pickedPhotos, maxSelectionCount: 20,
                      matching: .images, photoLibrary: .shared())
        .onChange(of: pickedPhotos) { addPickedPhotos() }
        .fullScreenCover(isPresented: $isTakingPhoto) {
            CameraPicker { data in
                isTakingPhoto = false
                guard let data else { return }
                Task {
                    if let small = await Task.detached(operation: { PhotoStore.downsized(data) }).value {
                        photos.append(PhotoDraft(data: small))
                    }
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $viewingPhoto) { photo in
            DraftPhotoViewer(drafts: $photos, start: photo.id)
        }
        .onAppear { if !isEditing { prefillInterval() } }
        .onChange(of: serviceChoice) { if !isEditing { prefillInterval() } }
        .onChange(of: customService) { if !isEditing { prefillInterval() } }
        .onChange(of: parts.first?.quantity) { if manualCost != nil { deriveSinglePartPrice() } }
        .task {
            if !isEditing {
                await focusAfterPresentation {
                    if startsTyped { serviceNameFocused = true } else { odometerFocused = true }
                }
            }
        }
    }

    private var serviceNameField: some View {
        TextField("Service name", text: $customService,
                  prompt: Text(startsTyped ? "What did you do?" : "Service name").foregroundStyle(Theme.faint))
            .font(.dipstick(16, relativeTo: .body))
            .foregroundStyle(Theme.text)
            .textInputAutocapitalization(.sentences)
            .submitLabel(.next)
            .onSubmit { odometerFocused = true }
            .focused($serviceNameFocused)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .panel(radius: Theme.Radius.field,
                   border: serviceNameFocused ? Theme.accent : Theme.panelBorder,
                   lineWidth: serviceNameFocused ? 1.5 : 1)
    }

    /// Services that fill in the name field: the car's scheduled ones first
    /// (like the Maintenance tab's chips), then its others, then the rest.
    /// Narrowed to matches once you start typing.
    private var suggestions: [String] {
        let all = FactorySchedule.scheduleFirst(
            serviceOptions.filter { $0 != Self.customChoice },
            schedule: vehicle.sortedScheduleItems.map(\.serviceType)
        )
        let typed = customService.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? all : all.filter { $0.localizedStandardContains(typed) }
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { option in
                    ChipButton(title: option,
                               isSelected: option.caseInsensitiveCompare(resolvedServiceType) == .orderedSame) {
                        customService = option
                        serviceNameFocused = false
                        odometerFocused = true
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .scrollClipDisabled()
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
                PartRow(part: $part, focusedPart: $focusedPart,
                        onSplit: { split(part.id, into: $0) }) {
                    parts.removeAll { $0.id == part.id }
                }
                FormDivider()
            }
            HStack(spacing: 0) {
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
                Rectangle().fill(Theme.divider).frame(width: 1, height: 28)
                Button {
                    hideKeyboard()
                    isChoosingReceiptSource = true
                } label: {
                    Label("From receipt", systemImage: "doc.text.viewfinder")
                        .font(.dipstick(14, .semibold, relativeTo: .body))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .panel(radius: Theme.Radius.field)
    }

    /// Splits a part into separate parts of one each, sharing its cost to the
    /// cent (a "pack of 2" bought as one line, two different items on one
    /// line…). Rename them after.
    private func split(_ id: UUID, into count: Int) {
        guard count >= 2, let index = parts.firstIndex(where: { $0.id == id }) else { return }
        let part = parts[index]
        let totalCents = Int(((Units.parseDecimal(part.cost) ?? 0) * Double(part.quantity) * 100).rounded())
        let pieces = (0..<count).map { totalCents / count + ($0 < totalCents % count ? 1 : 0) }
        let newParts = pieces.map { cents in
            PartDraft(name: part.name, partNumber: part.partNumber, quantity: 1,
                      cost: totalCents > 0 ? String(format: "%.2f", Double(cents) / 100) : "")
        }
        parts.replaceSubrange(index...index, with: newParts)
    }

    /// Adds a receipt's parts for this job (replacing an empty part row), and
    /// keeps the receipt with the service's photos if asked.
    /// Parts keep the receipt's prices; their share of the tax goes on top
    /// in the total cost ("Parts $2.97 + $0.29 tax and fees").
    private func addFromReceipt(_ found: [ReceiptSplit.Part], keepPhoto: Data?) {
        let costBefore = parsedCost ?? partsTotal
        parts.removeAll { $0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.cost.isEmpty && $0.partNumber.isEmpty }
        let tax = found.reduce(0) { $0 + $1.taxShare }
        if tax > 0.004 {
            manualCost = Self.money(costBefore + found.reduce(0) { $0 + $1.total })
        }
        parts += found.map { part in
            PartDraft(name: part.name, partNumber: part.partNumber ?? "", quantity: part.quantity,
                      cost: Self.price(part.priceEach))
        }
        if let keepPhoto {
            photos.append(PhotoDraft(data: keepPhoto,
                                     caption: "Receipt, \(date.formatted(date: .abbreviated, time: .omitted))"))
        }
    }

    /// A price each, to the cent when it divides evenly, else to 4 places so
    /// quantity × price still adds up to what was paid.
    private static func price(_ value: Double) -> String {
        let cents = (value * 100).rounded() / 100
        if abs(cents - value) < 0.00005 { return String(format: "%.2f", value) }
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        return text
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

    /// Notes and photos for next time; they show on the form whenever this
    /// service is logged again.
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Notes and photos") {
                Text("Shown next time")
                    .font(.dipstick(11.5, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
            TextField("Notes", text: $notes,
                      prompt: Text("Torque specs, part numbers, what to have ready…").foregroundStyle(Theme.faint),
                      axis: .vertical)
                .font(.dipstick(15, relativeTo: .body))
                .foregroundStyle(Theme.text)
                .lineLimit(3...)
                .focused($notesFocused)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
                .panel(radius: Theme.Radius.field, border: notesFocused ? Theme.accent : Theme.panelBorder,
                       lineWidth: notesFocused ? 1.5 : 1)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(photos) { photo in
                    Button {
                        hideKeyboard()
                        viewingPhoto = photo
                    } label: {
                        PhotoThumbnail(data: photo.data)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(photo.caption ?? "Photo")
                }
                Button {
                    hideKeyboard()
                    isChoosingPhotoSource = true
                } label: {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 4) {
                                Image(systemName: "photo.badge.plus").font(.system(size: 20, weight: .medium))
                                Text("Add")
                                    .font(.dipstick(12, .semibold, relativeTo: .caption))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Theme.accentText)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Theme.panelBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add photos")
            }
        }
        .padding(.top, 6)
    }

    private func addPickedPhotos() {
        let items = pickedPhotos
        guard !items.isEmpty else { return }
        pickedPhotos = []
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let small = await Task.detached(operation: { PhotoStore.downsized(data) }).value {
                    photos.append(PhotoDraft(data: small))
                }
            }
        }
    }

    private func hideKeyboard() {
        odometerFocused = false
        serviceNameFocused = false
        costFocused = false
        milesFocused = false
        monthsFocused = false
        focusedPart = nil
        notesFocused = false
    }

    // MARK: Interval prefill

    /// Offer the factory schedule's interval for this service, or else the one
    /// used last time on this vehicle, without overwriting anything typed.
    private func prefillInterval() {
        let current = MaintenanceSchedule.Interval(
            miles: Units.parseWholeNumber(everyMiles),
            months: Units.parseWholeNumber(everyMonths)
        )
        guard current.isEmpty || current == lastPrefill else { return }

        let previous = (vehicle.maintenanceEntries ?? [])
            .filter { $0.serviceType.caseInsensitiveCompare(resolvedServiceType) == .orderedSame }
            .max { $0.date < $1.date }
        let scheduled = vehicle.sortedScheduleItems
            .first { $0.serviceType.caseInsensitiveCompare(resolvedServiceType) == .orderedSame
                && ($0.effectiveRule.everyMiles != nil || $0.effectiveRule.everyMonths != nil) }
            .map { MaintenanceSchedule.Interval(miles: $0.effectiveRule.everyMiles, months: $0.effectiveRule.everyMonths) }
        let suggestion = scheduled ?? previous.map {
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

        // Photos: drop the ones removed, keep the rest in the form's order.
        let kept = Set(photos.compactMap { $0.existing?.persistentModelID })
        for old in target.photos ?? [] where !kept.contains(old.persistentModelID) {
            modelContext.delete(old)
        }
        for (order, draft) in photos.enumerated() {
            if let photo = draft.existing {
                photo.order = order
                photo.caption = draft.caption
            } else if let data = draft.data {
                let photo = ReferencePhoto(data: data, caption: draft.caption, order: order)
                modelContext.insert(photo)
                photo.entry = target
            }
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
    /// Split into this many separate parts.
    let onSplit: (Int) -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                TextField("Part name", text: $part.name,
                          prompt: Text("Part name").foregroundStyle(Theme.faint))
                    .font(.dipstick(15, .semibold, relativeTo: .body))
                    .foregroundStyle(Theme.text)
                    .focused(focusedPart, equals: .name(part.id))
                Menu {
                    Section("Split into separate parts, sharing the cost") {
                        ForEach(2...5, id: \.self) { count in
                            Button("Split into \(count)") { onSplit(count) }
                        }
                    }
                } label: {
                    Image(systemName: "square.split.2x1")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Split \(part.name.isEmpty ? "part" : part.name)")
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

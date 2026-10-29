//
//  FuelEntryFormView.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Log or edit a fill-up (design boards H and I). For a new fill-up the
/// odometer is never pre-filled: enter what the dash shows. After a scan,
/// gallons and total arrive filled in and only the odometer is left. A scan
/// that read the wrong numbers can be reported (and is, automatically, when a
/// scanned number is corrected): saving the fill-up then saves the photo with
/// the right numbers for tuning the reader (see `ScanReports`).
/// Shown inside `FillUpFlowView`, which handles the scanner.
struct FuelEntryFormView: View {
    let vehicle: Vehicle
    let entry: FuelEntry?
    /// Set when gallons and total came from the pump scanner.
    let scanned: PumpReadingParser.Reading?
    /// The scan's photo: of the reading above, or of a capture that couldn't
    /// be read.
    let scanEvidence: ScanEvidence?
    /// Open the scanner (SCAN PUMP / Rescan). Nil hides scanning (editing).
    let onScan: (() -> Void)?
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var date: Date
    @State private var odometer: String
    @State private var gallons: String
    @State private var totalCost: String
    @State private var isFullTank: Bool
    @State private var station: String
    @State private var notes: String
    @State private var isPickingDate = false
    @State private var showsOptional: Bool
    /// Save the scan's photo with the saved numbers, to improve scanning.
    @State private var reportsScan = false
    /// Turned off by hand: don't turn it back on when numbers change.
    @State private var reportDeclined = false

    @FocusState private var odometerFocused: Bool
    @FocusState private var gallonsFocused: Bool
    @FocusState private var totalFocused: Bool

    init(vehicle: Vehicle, entry: FuelEntry? = nil, scanned: PumpReadingParser.Reading? = nil,
         scanEvidence: ScanEvidence? = nil, onScan: (() -> Void)? = nil, onClose: @escaping () -> Void) {
        self.vehicle = vehicle
        self.entry = entry
        self.scanned = scanned
        self.scanEvidence = scanEvidence
        self.onScan = onScan
        self.onClose = onClose
        _date = State(initialValue: entry?.date ?? Date())
        _odometer = State(initialValue: entry.map { String($0.odometer) } ?? "")
        _gallons = State(initialValue: scanned.map { String(format: "%.3f", $0.gallons) }
            ?? entry.map { $0.gallons.formatted(.number.precision(.fractionLength(0...3)).grouping(.never)) } ?? "")
        _totalCost = State(initialValue: scanned.map { String(format: "%.2f", $0.total) }
            ?? entry.flatMap { $0.isCostKnown ? String(format: "%.2f", $0.totalCost) : nil } ?? "")
        _isFullTank = State(initialValue: entry?.isFullTank ?? true)
        _station = State(initialValue: entry?.station ?? "")
        _notes = State(initialValue: entry?.notes ?? "")
        _showsOptional = State(initialValue: !(entry?.station ?? "").isEmpty || !(entry?.notes ?? "").isEmpty)
    }

    private var isEditing: Bool { entry != nil }

    /// Average price of this car's last few fill-ups with a known cost, used to
    /// sanity-check a scanned reading.
    static func recentPricePerGallon(for vehicle: Vehicle) -> Double? {
        let recent = (vehicle.fuelEntries ?? [])
            .filter(\.isCostKnown)
            .sorted { $0.date > $1.date }
            .prefix(5)
        let gallons = recent.reduce(0) { $0 + $1.gallons }
        return gallons > 0 ? recent.reduce(0) { $0 + $1.totalCost } / gallons : nil
    }

    // MARK: Parsed values and validation

    private var parsedOdometer: Int? {
        Units.parseWholeNumber(odometer).flatMap { $0 >= 0 ? $0 : nil }
    }

    private var parsedGallons: Double? {
        Units.parseDecimal(gallons).flatMap { $0 > 0 ? $0 : nil }
    }

    /// Blank = cost unknown (stored as 0). nil = not a valid amount.
    private var parsedTotalCost: Double? {
        if totalCost.trimmingCharacters(in: .whitespaces).isEmpty { return 0 }
        return Units.parseDecimal(totalCost).flatMap { $0 >= 0 ? $0 : nil }
    }

    /// This vehicle's other fill-ups (excluding the one being edited).
    private var otherEntries: [FuelEntry] {
        (vehicle.fuelEntries ?? []).filter { $0.persistentModelID != entry?.persistentModelID }
    }

    private var duplicateEntry: FuelEntry? {
        guard let reading = parsedOdometer else { return nil }
        return otherEntries.first { $0.odometer == reading }
    }

    /// The highest-odometer fill-up above this reading, if any. Lower readings
    /// are allowed (e.g. backfilling old receipts) but worth pointing out.
    private var higherEntry: FuelEntry? {
        guard let reading = parsedOdometer else { return nil }
        return otherEntries.filter { $0.odometer > reading }.max { $0.odometer < $1.odometer }
    }

    private var canSave: Bool {
        parsedOdometer != nil && parsedGallons != nil && parsedTotalCost != nil && duplicateEntry == nil
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                FormHeader(title: isEditing ? "Edit fill-up" : "Log fill-up", vehicle: vehicle, onCancel: onClose)
                    .padding(.bottom, 6)

                if let onScan {
                    if scanned != nil {
                        scannedBanner(onRescan: onScan)
                    } else {
                        Button(action: onScan) {
                            Label("Scan pump", systemImage: "viewfinder")
                        }
                        .buttonStyle(BigActionButtonStyle(height: 56))
                        if scanEvidence != nil { unreadPhotoRow }
                    }
                }

                OdometerField(text: $odometer, focus: $odometerFocused)
                odometerProblem

                TileRow {
                    NumberTileField(label: "Gallons", text: $gallons, placeholder: "0.000",
                                    unit: "gal", focus: $gallonsFocused)
                    NumberTileField(label: "Total cost", text: $totalCost, placeholder: "$0.00",
                                    prefix: "$", focus: $totalFocused)
                }
                Text(priceCaption)
                    .font(.dipstick(11.5, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)

                detailsPanel
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.ground)
        .safeAreaInset(edge: .bottom) {
            FormSaveBar(
                title: "Save fill-up", isEnabled: canSave,
                isKeyboardUp: odometerFocused || gallonsFocused || totalFocused,
                onHideKeyboard: {
                    odometerFocused = false
                    gallonsFocused = false
                    totalFocused = false
                },
                onSave: save
            )
        }
        .tint(Theme.accent)
        .task {
            if !isEditing { await focusAfterPresentation { odometerFocused = true } }
        }
        .onChange(of: gallons) { reportIfCorrected() }
        .onChange(of: totalCost) { reportIfCorrected() }
    }

    /// Correcting a scanned number means the scan misread it.
    private func reportIfCorrected() {
        guard let scanned, scanEvidence != nil, !reportDeclined else { return }
        let gallonsChanged = parsedGallons.map { abs($0 - scanned.gallons) > 0.0005 } ?? true
        let totalChanged = parsedTotalCost.map { abs($0 - scanned.total) > 0.005 } ?? true
        if gallonsChanged || totalChanged { reportsScan = true }
    }

    private func scannedBanner(onRescan: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: reportsScan ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(reportsScan ? Theme.amber : Color.green)
                Text(reportsScan ? "Misread reported" : "Scanned from pump")
                    .font(.dipstick(14, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button("Rescan", action: onRescan)
                    .buttonStyle(SmallControlButtonStyle())
            }
            .frame(minHeight: 56)
            if scanEvidence != nil {
                FormDivider().padding(.leading, -16)
                HStack(spacing: 8) {
                    Text(reportsScan
                         ? "Fix the numbers below. Saving keeps the photo with them to improve scanning."
                         : "Numbers wrong?")
                        .font(.dipstick(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                    Spacer(minLength: 4)
                    Button(reportsScan ? "Undo" : "Report misread") {
                        reportsScan.toggle()
                        reportDeclined = !reportsScan
                    }
                    .font(.dipstick(13, .semibold, relativeTo: .footnote))
                    .foregroundStyle(Theme.accentText)
                    .frame(minHeight: Theme.minimumHitTarget)
                }
            }
        }
        .padding(.horizontal, 12)
        .panel(radius: Theme.Radius.button)
    }

    /// A capture that couldn't be read: offer to keep it for tuning.
    private var unreadPhotoRow: some View {
        Toggle(isOn: $reportsScan) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Save the unread photo")
                    .font(.dipstick(14, .semibold, relativeTo: .subheadline))
                    .foregroundStyle(Theme.text)
                Text("Kept with the numbers you save, to improve scanning")
                    .font(.dipstick(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .panel(radius: Theme.Radius.field)
    }

    @ViewBuilder
    private var odometerProblem: some View {
        if let duplicate = duplicateEntry {
            StatusLine(status: .overdue, text: "Already logged a fill-up at \(Units.miles(duplicate.odometer)) on \(duplicate.date.formatted(date: .abbreviated, time: .omitted))")
        } else if let higher = higherEntry {
            StatusLine(status: .dueSoon, text: "Lower than your \(higher.date.formatted(date: .abbreviated, time: .omitted)) fill-up at \(Units.miles(higher.odometer))")
        } else if let jump = Units.odometerJump(parsedOdometer, from: vehicle.currentOdometer, limit: 2_000) {
            StatusLine(status: .dueSoon, text: "\(Units.miles(jump)) more than \(vehicle.name)'s last reading. Check for a typo")
        }
    }

    private var priceCaption: String {
        if let gallons = parsedGallons, let cost = parsedTotalCost, cost > 0 {
            return "\(Units.pricePerGallon(cost / gallons)) · worked out from the other two"
        }
        if totalCost.isEmpty && parsedGallons != nil {
            return "No total? Leave it blank; spend stats will skip this fill-up."
        }
        return "Price per gallon is worked out from gallons and total"
    }

    private var detailsPanel: some View {
        VStack(spacing: 0) {
            Button { withAnimation { isPickingDate.toggle() } } label: {
                FormRow("Date") {
                    HStack(spacing: 6) {
                        Text(date.formRowText)
                            .font(.dipstick(15, .semibold, relativeTo: .body))
                            .foregroundStyle(Theme.text)
                        Image(systemName: isPickingDate ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isPickingDate {
                DatePicker("Date", selection: $date, in: ...Date.now.addingTimeInterval(86_400))
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(.horizontal, 8)
            }

            FormDivider()
            FormRow("Full tank", subtitle: "Turn off for a partial fill") {
                Toggle("Full tank", isOn: $isFullTank).labelsHidden().tint(Theme.accent)
            }

            FormDivider()
            Button { withAnimation { showsOptional.toggle() } } label: {
                FormRow("Station, notes") {
                    HStack(spacing: 6) {
                        Text("Optional")
                            .font(.dipstick(14, relativeTo: .body))
                            .foregroundStyle(Theme.muted)
                        Image(systemName: showsOptional ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showsOptional {
                VStack(spacing: 0) {
                    TextField("Station", text: $station,
                              prompt: Text("Station").foregroundStyle(Theme.faint))
                        .textInputAutocapitalization(.words)
                        .frame(minHeight: 44)
                    FormDivider().padding(.leading, -16)
                    TextField("Notes", text: $notes,
                              prompt: Text("Notes").foregroundStyle(Theme.faint), axis: .vertical)
                        .frame(minHeight: 44)
                }
                .font(.dipstick(15, relativeTo: .body))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 16)
            }
        }
        .panel(radius: Theme.Radius.field)
    }

    // MARK: Saving

    private func save() {
        guard let odometerValue = parsedOdometer,
              let gallonsValue = parsedGallons,
              let costValue = parsedTotalCost else { return }

        let target = entry ?? FuelEntry(odometer: odometerValue, gallons: gallonsValue, totalCost: costValue)
        target.date = date
        target.odometer = odometerValue
        target.gallons = gallonsValue
        target.totalCost = costValue
        target.isFullTank = isFullTank
        target.station = nilIfBlank(station)
        target.notes = nilIfBlank(notes)

        if entry == nil {
            modelContext.insert(target)
            target.vehicle = vehicle
        }
        vehicle.recordOdometer(odometerValue)
        modelContext.saveNow()
        if reportsScan, let scanEvidence {
            ScanReports.save(scanEvidence, total: costValue, gallons: gallonsValue)
        }
        onClose()
    }

    private func nilIfBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The whole fill-up flow in one full-screen cover: the pump scanner and the
/// form, switching in place. From Home it starts in the scanner; from the
/// Fuel tab (and for edits) it starts in the form.
struct FillUpFlowView: View {
    let vehicle: Vehicle
    var entry: FuelEntry?
    var startInScanner = false

    @Environment(\.dismiss) private var dismiss
    @State private var isScanning: Bool
    @State private var reading: PumpReadingParser.Reading?
    @State private var evidence: ScanEvidence?
    /// Bumped to rebuild the form with a new scan.
    @State private var formID = UUID()

    init(vehicle: Vehicle, entry: FuelEntry? = nil, startInScanner: Bool = false) {
        self.vehicle = vehicle
        self.entry = entry
        self.startInScanner = startInScanner
        _isScanning = State(initialValue: startInScanner && entry == nil)
    }

    var body: some View {
        ZStack {
            if isScanning {
                PumpScannerView(
                    vehicle: vehicle,
                    expectedPrice: FuelEntryFormView.recentPricePerGallon(for: vehicle),
                    onReading: { scan, photo in
                        reading = scan
                        evidence = photo
                        formID = UUID()
                        withAnimation { isScanning = false }
                    },
                    onEnterManually: { unread in
                        // Offer the unread photo, unless an earlier scan already filled the form.
                        if reading == nil, let unread {
                            evidence = unread
                            formID = UUID()
                        }
                        withAnimation { isScanning = false }
                    },
                    onClose: {
                        // From Home there's no form to go back to.
                        if startInScanner && reading == nil { dismiss() } else { withAnimation { isScanning = false } }
                    }
                )
                .transition(.opacity)
            } else {
                FuelEntryFormView(
                    vehicle: vehicle, entry: entry, scanned: reading, scanEvidence: evidence,
                    onScan: entry == nil ? { withAnimation { isScanning = true } } : nil,
                    onClose: { dismiss() }
                )
                .id(formID)
                .transition(.opacity)
            }
        }
    }
}

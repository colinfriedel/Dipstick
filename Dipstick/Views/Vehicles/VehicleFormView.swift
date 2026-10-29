//
//  VehicleFormView.swift
//  Dipstick
//

import SwiftUI
import SwiftData

/// Add a vehicle (pass nil) or edit one (design board K). The header previews
/// the chip, name and model as you type.
struct VehicleFormView: View {
    let vehicle: Vehicle?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var year: String
    @State private var make: String
    @State private var model: String
    @State private var vin: String
    @State private var odometer: String
    @State private var colorHex: String?
    @State private var colorName: String
    @State private var customColor: Color
    @State private var showsTripDetection = false
    @State private var connectionMessage: String?

    @FocusState private var focused: Field?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var odometerFocused: Bool

    private enum Field { case name, year, make, model, vin, colorName }

    /// Preset chip colors: red, gold, silver, blue, green, black, white.
    static let swatches = ["#B8433F", "#D4AE48", "#A4A9B0", "#4A6FA5", "#3E7A55", "#1E2126", "#EEF0F2"]

    init(vehicle: Vehicle? = nil) {
        self.vehicle = vehicle
        _name = State(initialValue: vehicle?.name ?? "")
        _year = State(initialValue: vehicle?.year.map(String.init) ?? "")
        _make = State(initialValue: vehicle?.make ?? "")
        _model = State(initialValue: vehicle?.model ?? "")
        _vin = State(initialValue: vehicle?.vin ?? "")
        _odometer = State(initialValue: vehicle.map { String($0.currentOdometer) } ?? "")
        _colorHex = State(initialValue: vehicle?.colorHex)
        _colorName = State(initialValue: vehicle?.colorName ?? "")
        _customColor = State(initialValue: vehicle?.colorHex.flatMap(Color.init(hexString:)) ?? Theme.accent)
    }

    private var isEditing: Bool { vehicle != nil }

    // MARK: Parsed values

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var parsedOdometer: Int? {
        let digits = odometer.filter { $0 != "," && !$0.isWhitespace }
        guard let value = Int(digits), value >= 0 else { return nil }
        return value
    }

    private var parsedYear: Int? { Int(year.trimmingCharacters(in: .whitespaces)) }

    private static let validYears = 1900...(Calendar.current.component(.year, from: Date()) + 2)

    private var yearIsValid: Bool {
        year.trimmingCharacters(in: .whitespaces).isEmpty
            || parsedYear.map(Self.validYears.contains) == true
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && parsedOdometer != nil && yearIsValid
    }

    private var previewModelLine: String {
        [year, make, model].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private var isCustomColor: Bool {
        colorHex.map { hex in !Self.swatches.contains { $0.caseInsensitiveCompare(hex) == .orderedSame } } ?? false
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(SmallControlButtonStyle())
                    Text(isEditing ? "EDIT VEHICLE" : "ADD VEHICLE")
                        .font(.dipstick(15, .semibold, relativeTo: .headline))
                        .tracking(2)
                        .foregroundStyle(Theme.text)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.bottom, 8)

                preview.padding(.bottom, 6)

                textPanel("Nickname", text: $name, field: .name, focusRing: true)
                    .textInputAutocapitalization(.words)

                TileRow {
                    textPanel("Year", text: $year, field: .year, mono: true)
                        .keyboardType(.numberPad)
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 96)
                    textPanel("Make", text: $make, field: .make)
                        .textInputAutocapitalization(.words)
                    textPanel("Model", text: $model, field: .model)
                        .textInputAutocapitalization(.words)
                }
                if !yearIsValid {
                    StatusLine(status: .overdue, text: "Enter a year between \(String(Self.validYears.lowerBound)) and \(String(Self.validYears.upperBound))")
                }

                textPanel("VIN · optional", text: $vin, field: .vin, mono: true, placeholder: "17 characters")
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

                OdometerField(text: $odometer, focus: $odometerFocused, size: 28)
                if !isEditing && odometer.isEmpty {
                    Text("Not sure of the exact reading? A close guess is fine. You can change it later.")
                        .font(.dipstick(11.5, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }

                SmallCapsLabel("Color").padding(.top, 8)
                swatchRow
                textPanel("Color name · optional", text: $colorName, field: .colorName, placeholder: "e.g. Redondo Red Pearl")
                    .textInputAutocapitalization(.words)

                tripDetection.padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.ground)
        .safeAreaInset(edge: .bottom) {
            FormSaveBar(
                title: "Save vehicle", isEnabled: canSave,
                isKeyboardUp: focused != nil || odometerFocused,
                onHideKeyboard: {
                    focused = nil
                    odometerFocused = false
                },
                onSave: save
            )
        }
        .tint(Theme.accent)
        .task {
            if !isEditing { await focusAfterPresentation { focused = .name } }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                CarChip(colorHex: colorHex, size: 14)
                Text(trimmedName.isEmpty ? "NEW VEHICLE" : trimmedName.uppercased())
                    .font(.dipstick(26, .semibold, relativeTo: .title))
                    .tracking(2)
                    .foregroundStyle(trimmedName.isEmpty ? Theme.faint : Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if !previewModelLine.isEmpty {
                Text(previewModelLine)
                    .font(.dipstick(13, relativeTo: .footnote))
                    .foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A 60pt field panel: small-caps label over a 17pt value.
    private func textPanel(_ label: String, text: Binding<String>, field: Field, mono: Bool = false,
                           placeholder: String = "", focusRing: Bool = true) -> some View {
        let isFocused = focused == field
        return VStack(alignment: .leading, spacing: 3) {
            SmallCapsLabel(label)
            TextField(label, text: text, prompt: Text(placeholder).foregroundStyle(Theme.faint))
                .font(mono ? .readout(17, relativeTo: .body) : .dipstick(17, .semibold, relativeTo: .body))
                .foregroundStyle(Theme.text)
                .focused($focused, equals: field)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .panel(radius: Theme.Radius.field,
               border: isFocused && focusRing ? Theme.accent : Theme.panelBorder,
               lineWidth: isFocused && focusRing ? 1.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture { focused = field }
    }

    private var swatchRow: some View {
        HStack(spacing: 6) {
            ForEach(Self.swatches, id: \.self) { hex in
                swatch(color: Color(hexString: hex) ?? .gray,
                       isSelected: colorHex?.caseInsensitiveCompare(hex) == .orderedSame) {
                    colorHex = hex
                }
                .accessibilityLabel(Self.swatchName(hex))
            }
            ColorPicker(selection: $customColor, supportsOpacity: false) {
                EmptyView()
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, minHeight: 36)
            .overlay {
                if isCustomColor {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.text, lineWidth: 2)
                        .padding(-4)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Custom color")
            .onChange(of: customColor) { colorHex = customColor.hexString }
        }
    }

    private func swatch(color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.panelBorder, lineWidth: 1))
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 36)
                .padding(3)
                .frame(maxWidth: .infinity)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.text, lineWidth: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private static func swatchName(_ hex: String) -> String {
        ["Red", "Gold", "Silver", "Blue", "Green", "Black", "White"][swatches.firstIndex(of: hex) ?? 0]
    }

    /// Collapsed row: the CarPlay/Bluetooth connections used to assign trips to
    /// this car automatically. Only shown when editing an existing car.
    @ViewBuilder
    private var tripDetection: some View {
        VStack(spacing: 0) {
            Button { withAnimation { showsTripDetection.toggle() } } label: {
                FormRow("Trip detection") {
                    HStack(spacing: 6) {
                        Text(connectionsSummary)
                            .font(.dipstick(14, relativeTo: .body))
                            .foregroundStyle(Theme.muted)
                        Image(systemName: showsTripDetection ? "chevron.down" : "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsTripDetection {
                if let vehicle {
                    ForEach(vehicle.connections, id: \.id) { connection in
                        FormDivider()
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(connection.name)
                                    .font(.dipstick(15, .semibold, relativeTo: .body))
                                    .foregroundStyle(Theme.text)
                                Text(connection.id)
                                    .font(.readout(11, relativeTo: .caption2))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Button {
                                vehicle.removeConnection(id: connection.id)
                                modelContext.saveNow()
                                connectionMessage = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(connection.name)")
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, 4)
                    }
                    FormDivider()
                    Button {
                        if let connection = CarConnection.current() {
                            if vehicle.knowsConnection(connection.id) {
                                connectionMessage = "\(connection.name) is already linked."
                            } else {
                                vehicle.addConnection(connection)
                                modelContext.saveNow()
                                connectionMessage = "Linked \(connection.name)."
                            }
                        } else {
                            connectionMessage = "Not connected to CarPlay or Bluetooth right now."
                        }
                    } label: {
                        Label("Add current connection", systemImage: "plus")
                            .font(.dipstick(14, .semibold, relativeTo: .body))
                            .foregroundStyle(Theme.accentText)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text(connectionHelp)
                    .font(.dipstick(12, relativeTo: .caption))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .panel(radius: Theme.Radius.field)
    }

    private var connectionsSummary: String {
        let count = vehicle?.connections.count ?? 0
        return count == 0 ? "Optional" : "\(count) linked"
    }

    private var connectionHelp: String {
        if let connectionMessage { return connectionMessage }
        return vehicle == nil
            ? "Save the car first, then connect to it (CarPlay or Bluetooth) and add the connection here."
            : "While connected to this car, tap Add. A car can have several (e.g. Bluetooth and CarPlay); trips on any of them are assigned to it."
    }

    // MARK: Saving

    private func save() {
        guard let odometerValue = parsedOdometer else { return }
        let target = vehicle ?? Vehicle(name: trimmedName)

        target.name = trimmedName
        target.year = parsedYear
        target.make = nilIfBlank(make)
        target.model = nilIfBlank(model)
        target.vin = nilIfBlank(vin)?.uppercased()
        target.currentOdometer = odometerValue
        target.colorHex = colorHex
        target.colorName = nilIfBlank(colorName)

        if vehicle == nil {
            modelContext.insert(target)
            // A general schedule until the car's own is added from its manual.
            target.loadSchedule(FactorySchedule.standard(forYear: target.year), into: modelContext)
            target.scheduleSource = FactorySchedule.standardSource
        }
        modelContext.saveNow()
        dismiss()
    }

    private func nilIfBlank(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Color {
    /// "#RRGGBB" for storing a picked color.
    var hexString: String? {
        guard let components = UIColor(self).cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                               intent: .defaultIntent, options: nil)?.components,
              components.count >= 3 else { return nil }
        let r = Int((components[0] * 255).rounded()), g = Int((components[1] * 255).rounded()), b = Int((components[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", min(max(r, 0), 255), min(max(g, 0), 255), min(max(b, 0), 255))
    }
}

#Preview("Add") {
    VehicleFormView()
        .modelContainer(for: Vehicle.self, inMemory: true)
}

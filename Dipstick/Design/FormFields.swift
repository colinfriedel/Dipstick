//
//  FormFields.swift
//  Dipstick
//

import SwiftUI

/// The ODOMETER panel in forms: digits typed into a hidden number field are
/// shown on the amber LCD. Accent border while focused. Never pre-filled for
/// new entries (the caller decides the starting text).
struct OdometerField: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var size: CGFloat = 32
    var label = "Odometer"

    private var miles: Int? { Units.parseWholeNumber(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SmallCapsLabel(label)
                Spacer()
                SmallCapsLabel("mi")
            }
            ZStack(alignment: .leading) {
                TextField("", text: digitsOnly)
                    .keyboardType(.numberPad)
                    .focused(focus)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .accessibilityLabel(label)
                    .accessibilityValue(miles.map { "\($0.formatted()) miles" } ?? "empty")
                HStack(spacing: 2) {
                    if focus.wrappedValue {
                        Caret(height: size * 0.95)
                    }
                    OdometerView(miles: miles, size: size, showsUnit: false, placeholder: miles == nil)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(radius: Theme.Radius.field,
               border: focus.wrappedValue ? Theme.accent : Theme.panelBorder,
               lineWidth: focus.wrappedValue ? 1.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
    }

    /// Up to 7 digits, nothing else.
    private var digitsOnly: Binding<String> {
        Binding(
            get: { text },
            set: { text = String($0.filter(\.isNumber).prefix(7)) }
        )
    }
}

/// A blinking accent text cursor.
private struct Caret: View {
    let height: CGFloat
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Theme.accent)
            .frame(width: 2, height: height)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) { visible = false }
            }
    }
}

/// A 92pt tile with a small-caps label and a big mono number field
/// (GALLONS, TOTAL COST, EVERY …).
struct NumberTileField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    var prefix: String?
    var unit: String?
    var keyboard: UIKeyboardType = .decimalPad
    var size: CGFloat = 30
    var height: CGFloat = 92
    var focus: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading) {
            SmallCapsLabel(label)
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if let prefix, !text.isEmpty {
                    Text(prefix).font(.readout(size, relativeTo: .title)).foregroundStyle(Theme.text)
                }
                // Sized to what's typed (or the placeholder), so the unit
                // follows the number instead of a fixed-width field.
                Text(text.isEmpty ? placeholder : text)
                    .font(.readout(size, relativeTo: .title))
                    .tracking(-size / 30)
                    .hidden()
                    .overlay(alignment: .leading) {
                        TextField(placeholder, text: $text,
                                  prompt: Text(placeholder).foregroundStyle(Theme.faint))
                            .font(.readout(size, relativeTo: .title))
                            .tracking(-size / 30)
                            .foregroundStyle(Theme.text)
                            .keyboardType(keyboard)
                            .focused(focus)
                            .frame(minWidth: 20)
                            .fixedSize()
                    }
                if let unit {
                    Text(unit)
                        .font(.dipstick(11, relativeTo: .caption2))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
        .panel(radius: Theme.Radius.tile,
               border: focus.wrappedValue ? Theme.accent : Theme.panelBorder,
               lineWidth: focus.wrappedValue ? 1.5 : 1)
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
        .accessibilityElement(children: .contain)
    }
}

/// Top bar of a form: Cancel, then the title with the car's chip.
struct FormHeader: View {
    let title: String
    let vehicle: Vehicle?
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button("Cancel", action: onCancel)
                .buttonStyle(SmallControlButtonStyle())
            if let vehicle { vehicle.chip }
            Text(title.uppercased())
                .font(.dipstick(15, .semibold, relativeTo: .headline))
                .tracking(2)
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
    }
}

/// A row inside a form PanelList: small-caps label on the left, content on the right.
struct FormRow<Trailing: View>: View {
    let label: String
    var subtitle: String?
    let trailing: Trailing

    init(_ label: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                SmallCapsLabel(label)
                if let subtitle {
                    Text(subtitle)
                        .font(.dipstick(12, relativeTo: .caption))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            trailing
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

/// Thin divider between FormRows in one panel.
struct FormDivider: View {
    var body: some View {
        Rectangle().fill(Theme.divider).frame(height: 1).padding(.leading, 16)
    }
}

extension Date {
    /// "Today, 2:00 PM" / "Oct 14, 2:00 PM".
    var formRowText: String {
        let time = formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(self) { return "Today, \(time)" }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday, \(time)" }
        return "\(formatted(.dateTime.month(.abbreviated).day())), \(time)"
    }
}

/// Bottom bar of a form: the Save button, plus a hide-keyboard button while
/// typing (number pads have no return key).
struct FormSaveBar: View {
    let title: String
    let isEnabled: Bool
    let isKeyboardUp: Bool
    let onHideKeyboard: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isKeyboardUp {
                Button(action: onHideKeyboard) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 20, weight: .regular))
                        .frame(width: 60, height: 60)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.button).fill(Theme.controlFill))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button)
                            .strokeBorder(Theme.controlBorder, lineWidth: 1.5))
                        .foregroundStyle(Theme.text)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide keyboard")
            }
            Button(title, action: onSave)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Theme.ground)
    }
}

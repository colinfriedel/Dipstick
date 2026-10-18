//
//  Components.swift
//  Dipstick
//

import SwiftUI

// Reusable pieces of the "instrument cluster" design (docs/Dipstick_Design_Spec.md §1).

// MARK: - Numbers

/// A numeric readout in Share Tech Mono with tight letter-spacing and the
/// decimal point pulled in (the monospace face gives "." a full cell).
struct MonoNumber: View {
    let text: String
    var size: CGFloat
    var color: Color = Theme.text
    var relativeTo: Font.TextStyle = .title

    var body: some View {
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        HStack(spacing: 0) {
            Text(String(parts[0]))
            if parts.count == 2 {
                Text(".").padding(.horizontal, -size * 0.12)
                Text(String(parts[1]))
            }
        }
        .font(.readout(size, relativeTo: relativeTo))
        .tracking(-size / 30)
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// An MPG value with its small "mpg" unit at the baseline; "--" when unknown.
struct MPGReadout: View {
    let value: Double?
    var size: CGFloat = 30
    var color: Color = Theme.text
    var unit = "mpg"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            MonoNumber(text: value.map { String(format: "%.1f", $0) } ?? "--",
                       size: size, color: value == nil ? Theme.gaugeEmpty : color)
            Text(unit)
                .font(.dipstick(11, relativeTo: .caption2))
                .foregroundStyle(Theme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(String(format: "%.1f", $0)) \(unit == "mpg" ? "miles per gallon" : unit)" } ?? "No value yet")
    }
}

/// The odometer as an amber LCD readout with faint "888888" ghost digits.
/// A dark window in light mode; no window in dark mode.
struct OdometerView: View {
    let miles: Int?
    var size: CGFloat = 24
    var showsUnit = true
    /// Shown dimmed in place of digits (e.g. an empty odometer field).
    var placeholder = false

    @Environment(\.colorScheme) private var colorScheme

    private var digits: String {
        guard let miles, !placeholder else { return "" }
        return String(format: "%06d", miles)
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            ZStack(alignment: .leading) {
                MonoNumber(text: String(repeating: "8", count: max(6, digits.count)),
                           size: size, color: Theme.lcdGhost)
                MonoNumber(text: digits, size: size, color: Theme.lcdDigits)
            }
            .padding(colorScheme == .light ? EdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9) : EdgeInsets())
            .background {
                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: Theme.Radius.lcdWindow).fill(Theme.lcdWindow)
                }
            }
            if showsUnit {
                SmallCapsLabel("mi")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(miles.map { "Odometer \($0.formatted()) miles" } ?? "Odometer not set")
    }
}

// MARK: - Labels

/// Small uppercase label: "CITY", "ODOMETER".
struct SmallCapsLabel: View {
    let text: String
    var color: Color = Theme.muted
    init(_ text: String, color: Color = Theme.muted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.dipstick(10, .semibold, relativeTo: .caption2))
            .tracking(1.5)
            .foregroundStyle(color)
    }
}

/// Section title with optional trailing detail: "FILL-UPS … Avg 26.7".
struct SectionTitle<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.dipstick(12, .semibold, relativeTo: .footnote))
                .tracking(2)
                .foregroundStyle(Theme.muted)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
    }
}

// MARK: - Panels and tiles

extension View {
    /// The standard panel: panel fill, thin border, rounded corners.
    func panel(radius: CGFloat = Theme.Radius.panelList, border: Color = Theme.panelBorder,
               lineWidth: CGFloat = 1) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(border, lineWidth: lineWidth))
    }
}

/// A labeled readout tile (CITY, ALL-TIME…). The highlighted variant has an
/// accent border and accent number.
struct ReadoutTile<Value: View>: View {
    let label: String
    var highlighted = false
    var height: CGFloat = 92
    let value: Value

    init(_ label: String, highlighted: Bool = false, height: CGFloat = 92, @ViewBuilder value: () -> Value) {
        self.label = label
        self.highlighted = highlighted
        self.height = height
        self.value = value()
    }

    var body: some View {
        VStack(alignment: .leading) {
            SmallCapsLabel(label)
            Spacer(minLength: 4)
            value
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
        .panel(radius: Theme.Radius.tile,
               border: highlighted ? Theme.accent : Theme.panelBorder,
               lineWidth: highlighted ? 1.5 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// Rows in one rounded panel, separated by divider lines.
struct PanelList<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    let row: (Data.Element) -> Row

    init(_ data: Data, @ViewBuilder row: @escaping (Data.Element) -> Row) {
        self.data = data
        self.row = row
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
                if index > 0 {
                    Rectangle().fill(Theme.divider).frame(height: 1).padding(.leading, 16)
                }
                row(element)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
            }
        }
        .panel()
    }
}

// MARK: - Buttons

/// Full-width LOG FILL-UP / LOG SERVICE button.
struct BigActionButtonStyle: ButtonStyle {
    var height: CGFloat = 60

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(BigActionLabelStyle())
            .font(.dipstick(16, .semibold, relativeTo: .headline))
            .tracking(2)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.button)
                .fill(configuration.isPressed ? Theme.selectedFill : Theme.controlFill))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.button)
                .strokeBorder(Theme.controlBorder, lineWidth: 1.5))
            .foregroundStyle(Theme.text)
    }
}

private struct BigActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon.font(.system(size: 22, weight: .regular))
            configuration.title
                .font(.dipstick(16, .semibold, relativeTo: .headline))
                .tracking(2)
                .textCase(.uppercase)
        }
    }
}

/// Accent-filled Save / Import button at the bottom of forms.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dipstick(16, .semibold, relativeTo: .headline))
            .tracking(2)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.button)
                .fill(Theme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35)))
            .foregroundStyle(Theme.onAccent)
    }
}

/// Small 44pt toolbar-style button (back, Edit, more, +).
struct SmallControlButtonStyle: ButtonStyle {
    var foreground: Color = Theme.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dipstick(14, .semibold, relativeTo: .subheadline))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(minWidth: Theme.minimumHitTarget, minHeight: Theme.minimumHitTarget)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(configuration.isPressed ? Theme.selectedFill : Theme.controlSmallFill))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.controlSmallBorder, lineWidth: 1))
    }
}

// MARK: - Chips, pills, status

/// A small square in the car's color, before its name everywhere.
struct CarChip: View {
    let colorHex: String?
    var size: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.carChip)
            .fill(colorHex.flatMap(Color.init(hexString:)) ?? Theme.faint)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension Vehicle {
    var chip: CarChip { CarChip(colorHex: colorHex) }
}

/// Red pill with a warning triangle and a count of due/overdue services.
struct CountPill: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 9, weight: .semibold))
            MonoNumber(text: "\(count)", size: 12, color: Theme.red, relativeTo: .caption)
        }
        .foregroundStyle(Theme.red)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.redPillFill))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.redPillBorder, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) service\(count == 1 ? "" : "s") need attention")
    }
}

extension MaintenanceDueCalculator.Status {
    /// Color for status text and icons (never used alone: always with an icon).
    var tint: Color {
        switch self {
        case .ok: Theme.muted
        case .dueSoon: Theme.amber
        case .overdue: Theme.red
        }
    }

    var icon: String {
        switch self {
        case .ok: "checkmark.circle"
        case .dueSoon: "clock"
        case .overdue: "exclamationmark.triangle"
        }
    }
}

/// Icon plus text in the status color: "Next 56,798 mi · 298 mi left".
struct StatusLine: View {
    let status: MaintenanceDueCalculator.Status
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: status.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
        }
        .font(.dipstick(12, .semibold, relativeTo: .caption))
        .foregroundStyle(status.tint)
        .accessibilityElement(children: .combine)
    }
}

/// A 36pt capsule chip; selected = accent border on the selected fill.
struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.dipstick(13, .semibold, relativeTo: .subheadline))
                .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Capsule().fill(isSelected ? Theme.selectedFill : Theme.panel))
                .overlay(Capsule().strokeBorder(isSelected ? Theme.accent : Theme.panelBorder,
                                                lineWidth: isSelected ? 1.5 : 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - List rows

/// Where a row sits in a panel made of separate list rows.
enum PanelRowPosition {
    case only, first, middle, last

    static func of(_ index: Int, count: Int) -> Self {
        switch (index, count) {
        case (_, 1): .only
        case (0, _): .first
        case (count - 1, _): .last
        default: .middle
        }
    }
}

extension View {
    /// A full-width custom row: no list background, separator or default insets.
    func plainRow(top: CGFloat = 5, bottom: CGFloat = 5) -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
    }

    /// One row of a PanelList-style panel built from separate list rows, so
    /// each row keeps swipe actions. Draws its slice of the rounded, bordered
    /// panel and the divider above it.
    func panelRow(_ position: PanelRowPosition) -> some View {
        padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(PanelRowBackground(position: position).padding(.horizontal, 16))
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
    }
}

/// A slice of a rounded, bordered panel: the full panel shape is drawn taller
/// than the row and clipped, so stacked rows read as one panel.
private struct PanelRowBackground: View {
    let position: PanelRowPosition

    var body: some View {
        GeometryReader { proxy in
            let radius = Theme.Radius.panelList
            let extraTop: CGFloat = (position == .first || position == .only) ? 0 : radius * 2
            let extraBottom: CGFloat = (position == .last || position == .only) ? 0 : radius * 2
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: radius)
                    .fill(Theme.panel)
                    .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.panelBorder, lineWidth: 1))
                    .frame(height: proxy.size.height + extraTop + extraBottom)
                    .offset(y: -extraTop)
                if position == .middle || position == .last {
                    Rectangle().fill(Theme.divider).frame(height: 1).padding(.leading, 16)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .clipped()
        }
    }
}

/// The 3-way tab switch in vehicle detail.
struct TabSwitch<Tab: Hashable & Identifiable>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    let title: (Tab) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                let isSelected = tab == selection
                Button { selection = tab } label: {
                    Text(title(tab))
                        .font(.dipstick(14, .semibold, relativeTo: .subheadline))
                        .foregroundStyle(isSelected ? Theme.text : Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 11)
                            .fill(isSelected ? Theme.selectedFill : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 11)
                            .strokeBorder(isSelected ? Theme.selectedBorder : Color.clear, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(4)
        .panel(radius: 14)
    }
}

// MARK: - Large text

/// Lays out side-by-side tiles in a row, or stacked at accessibility text
/// sizes so big numbers don't get squeezed or cut off.
struct TileRow<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
    }
}

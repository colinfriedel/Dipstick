//
//  Theme.swift
//  Dipstick
//

import SwiftUI
import UIKit

/// Design tokens from docs/Dipstick_Design_Spec.md ("instrument cluster") and
/// docs/Dipstick_Design_Spec_Light.md. Every color adapts to light/dark mode;
/// views use these tokens, never raw hex values.
enum Theme {
    // MARK: Colors

    static let ground = Color(light: 0xF2F3F5, dark: 0x07080A)
    static let panel = Color(light: 0xFFFFFF, dark: 0x101216)
    static let panelBorder = Color(light: 0xD9DDE3, dark: 0x23272E)
    static let divider = Color(light: 0xECEEF1, dark: 0x1C2026)

    /// Big action buttons (LOG FILL-UP, LOG SERVICE).
    static let controlFill = Color(light: 0xFFFFFF, dark: 0x171A1F)
    static let controlBorder = Color(light: 0xAEB6C2, dark: 0x4A5260)
    /// Small 44pt buttons (back, Edit, more).
    static let controlSmallFill = panel
    static let controlSmallBorder = Color(light: 0xCBD1D9, dark: 0x2A2F37)

    /// Selected tab or chip.
    static let selectedFill = Color(light: 0xE6EAF0, dark: 0x1E232B)
    static let selectedBorder = Color(light: 0xBFC7D2, dark: 0x343B46)

    static let text = Color(light: 0x14181F, dark: 0xDCE6F2)
    static let muted = Color(light: 0x5A6472, dark: 0x8A94A3)
    /// Placeholders and neutral chart bars.
    static let faint = Color(light: 0x8A94A3, dark: 0x5B6676)

    static let gaugeTick = Color(light: 0xC3CAD4, dark: 0x3A414B)
    /// Empty gauge value and "--" text.
    static let gaugeEmpty = Color(light: 0x8A94A3, dark: 0x6B7482)

    /// Overdue, errors.
    static let red = Color(light: 0xD63A2B, dark: 0xFF5A4A)
    static let redPillFill = Color(light: 0xFDE8E5, dark: 0x2A1210)
    static let redPillBorder = Color(light: 0xF0B8B1, dark: 0x5A2420)

    /// "Due soon" status text and icons.
    static let amber = Color(light: 0xB26A00, dark: 0xFFB000)

    /// Odometer LCD: the same amber digits in both modes, on a dark window in
    /// light mode (see `OdometerView`).
    static let lcdDigits = Color(hex: 0xFFB000)
    static let lcdGhost = Color(hex: 0x2A2108)
    static let lcdWindow = Color(hex: 0x14181F)

    /// The one accent color. App-wide; a Settings screen can change it later
    /// (alternates in the spec: 0x4FD1C5, 0x7CA8FF, 0xFFB000).
    static let accent = Color(hex: 0xFF6A2B)
    /// Small accent-colored text (links like "Add part"). The accent is too
    /// light for small text on white, so light mode uses the text color
    /// (light spec: "do not use the accent for small body text").
    static let accentText = Color(light: 0x14181F, dark: 0xFF6A2B)
    /// Text on accent-filled buttons, in both modes.
    static let onAccent = Color(hex: 0x07080A)

    // MARK: Shape

    enum Radius {
        static let panelList: CGFloat = 18
        static let tile: CGFloat = 16
        static let button: CGFloat = 16
        static let field: CGFloat = 14
        static let lcdWindow: CGFloat = 8
        static let carChip: CGFloat = 3.5
    }

    /// Minimum hit target for every tappable control.
    static let minimumHitTarget: CGFloat = 44
}

// MARK: - Fonts

extension Font {
    enum DipstickWeight {
        case medium, semibold
        var fontName: String {
            switch self {
            case .medium: "ChakraPetch-Medium"
            case .semibold: "ChakraPetch-SemiBold"
            }
        }
    }

    /// Chakra Petch UI text. Scales with Dynamic Type relative to `textStyle`.
    static func dipstick(_ size: CGFloat, _ weight: DipstickWeight = .medium,
                         relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom(weight.fontName, size: size, relativeTo: textStyle)
    }

    /// Share Tech Mono for numeric readouts (odometer, MPG, costs, gallons).
    static func readout(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        .custom("ShareTechMono-Regular", size: size, relativeTo: textStyle)
    }
}

// MARK: - Color helpers

extension Color {
    /// A fixed color from a 0xRRGGBB value.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// A color that switches with the light/dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }

    /// Parses "#RRGGBB" or "RRGGBB" (for `Vehicle.colorHex`).
    init?(hexString: String) {
        let digits = hexString.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value)
    }
}

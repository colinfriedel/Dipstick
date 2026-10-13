//
//  Units.swift
//  Dipstick
//

import Foundation

/// The single place that turns numbers into display strings, so switching to
/// km / liters later means changing this file only.
enum Units {
    static func miles(_ value: Int) -> String {
        "\(value.formatted()) mi"
    }

    static func gallons(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...3)))) gal"
    }

    static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }

    /// Gas prices are quoted to a tenth of a cent, e.g. $3.459.
    static func pricePerGallon(_ value: Double) -> String {
        "\(value.formatted(.currency(code: "USD").precision(.fractionLength(3))))/gal"
    }

    /// Fuel cost per mile, e.g. $0.117/mi.
    static func costPerMile(_ value: Double) -> String {
        "\(value.formatted(.currency(code: "USD").precision(.fractionLength(3))))/mi"
    }

    static func mpg(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1)))) mpg"
    }

    /// Parses a typed number, ignoring "$", "," and spaces.
    static func parseDecimal(_ text: String) -> Double? {
        let cleaned = text.filter { !"$, ".contains($0) }
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    static func parseWholeNumber(_ text: String) -> Int? {
        Int(text.filter { !", ".contains($0) })
    }
}

import Foundation

extension FormatStyle where Self == FloatingPointFormatStyle<Double>.Currency {
    /// Currency in the device's locale (single-user app, so one currency is fine).
    static var money: Self {
        .currency(code: Locale.current.currency?.identifier ?? "USD")
    }
}

extension FormatStyle where Self == FloatingPointFormatStyle<Double> {
    /// A plain number rounded to one decimal place (gallons, MPG).
    static var oneDecimal: Self {
        .number.precision(.fractionLength(0...1))
    }
}

extension String {
    /// Trimmed, or nil if it's empty after trimming.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

import Foundation

/// A calendar day with no time or timezone — the client-side mirror of the
/// backend's `models.Date`. The API sends these as `"YYYY-MM-DD"` strings, which
/// `JSONDecoder`'s built-in `Date` handling doesn't parse, so this type is its
/// own `Codable` (encoding/decoding as that string).
struct CalendarDate: Codable, Hashable, Comparable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The calendar day containing `date`, in the given calendar (device local by default).
    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    static var today: CalendarDate { CalendarDate(Date()) }

    // MARK: Codable ("YYYY-MM-DD")

    init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Expected YYYY-MM-DD, got \"\(string)\""
            ))
        }
        self.init(year: y, month: m, day: d)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }

    // MARK: Conversions & display

    var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// A real `Date` at midnight, for `DatePicker` binding and formatting.
    var date: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    /// "Mar 14, 2024"
    var displayString: String {
        date.formatted(.dateTime.year().month(.abbreviated).day())
    }

    static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

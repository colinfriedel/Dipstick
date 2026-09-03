import Foundation
import Testing
@testable import Dipstick

struct CalendarDateTests {

    @Test func decodesFromISOString() throws {
        let json = Data(#""2024-03-14""#.utf8)
        let date = try JSONDecoder().decode(CalendarDate.self, from: json)
        #expect(date == CalendarDate(year: 2024, month: 3, day: 14))
    }

    @Test func encodesToISOString() throws {
        let data = try JSONEncoder().encode(CalendarDate(year: 2024, month: 3, day: 4))
        #expect(String(decoding: data, as: UTF8.self) == #""2024-03-04""#)
    }

    @Test func rejectsBadStrings() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(CalendarDate.self, from: Data(#""March 14""#.utf8))
        }
    }

    @Test func isComparable() {
        #expect(CalendarDate(year: 2024, month: 1, day: 31) < CalendarDate(year: 2024, month: 2, day: 1))
        #expect(CalendarDate(year: 2023, month: 12, day: 31) < CalendarDate(year: 2024, month: 1, day: 1))
    }

    @Test func roundTripsThroughDate() {
        let original = CalendarDate(year: 2022, month: 7, day: 9)
        #expect(CalendarDate(original.date) == original)
    }
}

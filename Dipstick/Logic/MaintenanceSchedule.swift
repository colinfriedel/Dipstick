//
//  MaintenanceSchedule.swift
//  Dipstick
//

import Foundation

/// Converts between a service interval ("every 5,000 mi or 6 months") and the
/// due mileage/date stored on an entry.
enum MaintenanceSchedule {
    struct Interval: Equatable {
        var miles: Int?
        var months: Int?

        var isEmpty: Bool { miles == nil && months == nil }
    }

    struct Due: Equatable {
        var odometer: Int?
        var date: Date?
    }

    static func nextDue(
        odometer: Int,
        date: Date,
        every interval: Interval,
        calendar: Calendar = .current
    ) -> Due {
        Due(
            odometer: interval.miles.map { odometer + $0 },
            date: interval.months.flatMap { calendar.date(byAdding: .month, value: $0, to: date) }
        )
    }

    /// The interval an entry was logged with, recovered from its due values.
    static func interval(
        odometer: Int,
        date: Date,
        due: Due,
        calendar: Calendar = .current
    ) -> Interval {
        let miles = due.odometer.map { $0 - odometer }.flatMap { $0 > 0 ? $0 : nil }
        let months = due.date
            .flatMap { months(from: date, to: $0, calendar: calendar) }
            .flatMap { $0 > 0 ? $0 : nil }
        return Interval(miles: miles, months: months)
    }

    /// Whole months between two dates. Adding months can clamp the day
    /// (Jan 31 + 1 month = Feb 28), which a plain month difference reads as
    /// 0 months, so check which count actually lands on the due date.
    private static func months(from start: Date, to end: Date, calendar: Calendar) -> Int? {
        guard let counted = calendar.dateComponents([.month], from: start, to: end).month else {
            return nil
        }
        let landsOnDue = { (months: Int) in
            calendar.date(byAdding: .month, value: months, to: start)
                .map { calendar.isDate($0, inSameDayAs: end) } ?? false
        }
        return [counted, counted + 1].first(where: landsOnDue) ?? counted
    }
}

extension MaintenanceSchedule.Due {
    /// "61,400 mi or Apr 12, 2027", or nil when nothing is due.
    var summary: String? {
        let parts = [
            odometer.map(Units.miles),
            date.map { $0.formatted(date: .abbreviated, time: .omitted) },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " or ")
    }
}

extension MaintenanceEntry {
    var due: MaintenanceSchedule.Due {
        .init(odometer: nextDueOdometer, date: nextDueDate)
    }
}

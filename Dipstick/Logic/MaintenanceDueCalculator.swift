//
//  MaintenanceDueCalculator.swift
//  Dipstick
//

import Foundation
import SwiftData

/// Works out which services are OK, due soon, or overdue for one vehicle.
///
/// For each service type only the most recent record counts: its due mileage
/// and date are compared with the vehicle's current odometer and today. If the
/// latest record has no next-due set, that service isn't tracked.
enum MaintenanceDueCalculator {
    /// "Due soon" window. Tune here.
    static let soonMiles = 1_000
    static let soonDays = 30

    enum Status: Int, Comparable {
        case ok, dueSoon, overdue
        static func < (a: Status, b: Status) -> Bool { a.rawValue < b.rawValue }
    }

    struct Record<ID: Hashable> {
        let id: ID
        let serviceType: String
        let date: Date
        let odometer: Int
        let due: MaintenanceSchedule.Due
    }

    struct Item<ID: Hashable> {
        let id: ID
        let serviceType: String
        let due: MaintenanceSchedule.Due
        /// Negative when overdue.
        let milesLeft: Int?
        let daysLeft: Int?
        let status: Status
        /// When the latest record of this service was done.
        let lastDone: Date

        /// How much of the due-soon window is left (lower = more urgent), using
        /// whichever of miles or days is closer.
        var urgency: Double {
            [
                milesLeft.map { Double($0) / Double(soonMiles) },
                daysLeft.map { Double($0) / Double(soonDays) },
            ].compactMap { $0 }.min() ?? .infinity
        }

        /// Whether the miles side is the more urgent one (for the summary text).
        var milesAreMoreUrgent: Bool {
            guard let milesLeft else { return false }
            guard let daysLeft else { return true }
            return Double(milesLeft) / Double(soonMiles) <= Double(daysLeft) / Double(soonDays)
        }

        /// Short form for status lines: "6 yr overdue", "298 mi left", "12 days left".
        var shortSummary: String {
            if milesAreMoreUrgent, let milesLeft {
                if milesLeft < 0 { return "\((-milesLeft).formatted()) mi overdue" }
                if milesLeft == 0 { return "due now" }
                return "\(milesLeft.formatted()) mi left"
            }
            guard let daysLeft else { return "" }
            if daysLeft == 0 { return "due today" }
            return "\(Self.span(days: abs(daysLeft))) \(daysLeft < 0 ? "overdue" : "left")"
        }

        /// "Due Aug 2020" or "Due 56,798 mi", whichever drives the status.
        var dueLabel: String {
            if milesAreMoreUrgent, let odometer = due.odometer {
                return "Due \(odometer.formatted()) mi"
            }
            if let date = due.date {
                return "Due \(date.formatted(.dateTime.month(.abbreviated).year()))"
            }
            return due.odometer.map { "Due \($0.formatted()) mi" } ?? ""
        }

        /// "Next 56,798 mi" or "Next Aug 2020".
        var nextLabel: String {
            "Next" + dueLabel.dropFirst("Due".count)
        }

        /// 2260 days → "6 yr", 75 → "2 mo", 1 → "1 day".
        static func span(days: Int) -> String {
            switch days {
            case 365...: "\(days / 365) yr"
            case 30...: "\(days / 30) mo"
            case 1: "1 day"
            default: "\(days) days"
            }
        }

        /// "overdue by 320 mi", "due in 12 days", "due today".
        var summary: String {
            if milesAreMoreUrgent, let milesLeft {
                if milesLeft < 0 { return "overdue by \(Units.miles(-milesLeft))" }
                if milesLeft == 0 { return "due now" }
                return "due in \(Units.miles(milesLeft))"
            }
            if let daysLeft {
                switch daysLeft {
                case ..<(-1): return "overdue by \(-daysLeft) days"
                case -1: return "overdue by 1 day"
                case 0: return "due today"
                case 1: return "due tomorrow"
                default: return "due in \(daysLeft) days"
                }
            }
            return ""
        }
    }

    /// One item per tracked service type, most urgent first.
    static func items<ID>(
        for records: [Record<ID>],
        currentOdometer: Int,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> [Item<ID>] {
        let latestByType = Dictionary(grouping: records) { $0.serviceType.lowercased() }
            .compactMapValues { group in
                group.max { ($0.date, $0.odometer) < ($1.date, $1.odometer) }
            }

        return latestByType.values.compactMap { record -> Item<ID>? in
            guard record.due.odometer != nil || record.due.date != nil else { return nil }

            let milesLeft = record.due.odometer.map { $0 - currentOdometer }
            let daysLeft = record.due.date.flatMap {
                calendar.dateComponents(
                    [.day],
                    from: calendar.startOfDay(for: today),
                    to: calendar.startOfDay(for: $0)
                ).day
            }
            let status = max(
                milesLeft.map { status(left: $0, soon: soonMiles) } ?? .ok,
                daysLeft.map { status(left: $0, soon: soonDays) } ?? .ok
            )
            return Item(
                id: record.id, serviceType: record.serviceType, due: record.due,
                milesLeft: milesLeft, daysLeft: daysLeft, status: status,
                lastDone: record.date
            )
        }
        .sorted { ($0.status, -$0.urgency) > ($1.status, -$1.urgency) }
    }

    private static func status(left: Int, soon: Int) -> Status {
        if left < 0 { return .overdue }
        if left <= soon { return .dueSoon }
        return .ok
    }
}

extension Vehicle {
    /// Due status for each tracked service on this vehicle, most urgent first.
    func maintenanceDueItems(today: Date = Date()) -> [MaintenanceDueCalculator.Item<PersistentIdentifier>] {
        let records = (maintenanceEntries ?? []).map {
            MaintenanceDueCalculator.Record(
                id: $0.persistentModelID, serviceType: $0.serviceType,
                date: $0.date, odometer: $0.odometer, due: $0.due
            )
        }
        return MaintenanceDueCalculator.items(for: records, currentOdometer: currentOdometer, today: today)
    }
}

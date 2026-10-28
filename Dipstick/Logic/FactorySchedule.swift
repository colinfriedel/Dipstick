//
//  FactorySchedule.swift
//  Dipstick
//

import Foundation
import SwiftData

/// A car's factory maintenance schedule and how far along each item is,
/// measured from the latest logged service of the matching type.
enum FactorySchedule {
    struct Rule: Equatable {
        var everyMiles: Int?
        var everyMonths: Int?
        var firstMiles: Int?
        var firstMonths: Int?

        var isTracked: Bool {
            [everyMiles, everyMonths, firstMiles, firstMonths].contains { $0 != nil }
        }

        var hasFirst: Bool { firstMiles != nil || firstMonths != nil }

        /// "Every 10,000 mi or 6 mo", "Every 3 yr",
        /// "At 120,000 mi or 10 yr, then every 60,000 mi or 5 yr".
        var summary: String? {
            let every = Self.phrase(miles: everyMiles, months: everyMonths)
            let first = Self.phrase(miles: firstMiles, months: firstMonths)
            switch (first, every) {
            case let (first?, every?): return "At \(first), then every \(every)"
            case let (first?, nil): return "At \(first)"
            case let (nil, every?): return "Every \(every)"
            case (nil, nil): return nil
            }
        }

        /// "10,000 mi or 6 mo"; nil when both are missing.
        static func phrase(miles: Int?, months: Int?) -> String? {
            let parts = [miles.map { "\($0.formatted()) mi" }, months.map(monthsText)].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " or ")
        }

        /// 36 → "3 yr", 18 → "18 mo".
        nonisolated static func monthsText(_ months: Int) -> String {
            months % 12 == 0 ? "\(months / 12) yr" : "\(months) mo"
        }
    }

    struct LastDone: Equatable {
        let odometer: Int
        let date: Date
    }

    struct Progress {
        let due: MaintenanceSchedule.Due
        /// Negative when overdue.
        let milesLeft: Int?
        let daysLeft: Int?
        /// 0 right after the service, 1 when it's due, above 1 when overdue.
        /// nil when there's nothing to measure from.
        let fraction: Double?
        let status: MaintenanceDueCalculator.Status
        let lastDone: LastDone?

        /// Never logged, and either already past its first due point or only
        /// timed (so there's no start date to count from).
        var needsRecord: Bool {
            lastDone == nil && (fraction == nil || status != .ok)
        }

        /// "298 mi left", "6 yr overdue", "due now".
        var shortSummary: String { asDueItem.shortSummary }

        /// "Due 66,500 mi" or "Due Oct 2029".
        var dueLabel: String { asDueItem.dueLabel }

        private var asDueItem: MaintenanceDueCalculator.Item<Int> {
            .init(id: 0, serviceType: "", due: due, milesLeft: milesLeft, daysLeft: daysLeft,
                  status: status, lastDone: lastDone?.date ?? .distantPast)
        }
    }

    /// Progress toward the next time this item is due. Never logged: counts
    /// from 0 mi toward the first interval (or the regular one). Logged: counts
    /// from the last time toward the regular interval. nil if the rule has no
    /// interval at all.
    static func progress(
        for rule: Rule,
        lastDone: LastDone?,
        currentOdometer: Int,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Progress? {
        guard rule.isTracked else { return nil }

        var due = MaintenanceSchedule.Due()
        var fractions: [Double] = []
        if let lastDone {
            if let miles = rule.everyMiles, miles > 0 {
                due.odometer = lastDone.odometer + miles
                fractions.append(Double(currentOdometer - lastDone.odometer) / Double(miles))
            }
            if let months = rule.everyMonths, months > 0,
               let date = calendar.date(byAdding: .month, value: months, to: lastDone.date) {
                due.date = date
                let span = date.timeIntervalSince(lastDone.date)
                fractions.append(today.timeIntervalSince(lastDone.date) / span)
            }
        } else if let miles = rule.firstMiles ?? rule.everyMiles, miles > 0 {
            // No start date is known for a never-logged item, so only miles count.
            due.odometer = miles
            fractions.append(Double(currentOdometer) / Double(miles))
        }

        let milesLeft = due.odometer.map { $0 - currentOdometer }
        let daysLeft = due.date.flatMap {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: today),
                                    to: calendar.startOfDay(for: $0)).day
        }
        let status = max(
            milesLeft.map { MaintenanceDueCalculator.status(left: $0, soon: MaintenanceDueCalculator.soonMiles) } ?? .ok,
            daysLeft.map { MaintenanceDueCalculator.status(left: $0, soon: MaintenanceDueCalculator.soonDays) } ?? .ok
        )
        return Progress(due: due, milesLeft: milesLeft, daysLeft: daysLeft,
                        fraction: fractions.max().map { max($0, 0) }, status: status, lastDone: lastDone)
    }

    /// Latest record of a service type, matched ignoring case.
    static func lastDone(
        _ serviceType: String,
        in records: [(serviceType: String, odometer: Int, date: Date)]
    ) -> LastDone? {
        records
            .filter { $0.serviceType.caseInsensitiveCompare(serviceType) == .orderedSame }
            .max { ($0.date, $0.odometer) < ($1.date, $1.odometer) }
            .map { LastDone(odometer: $0.odometer, date: $0.date) }
    }

    /// Service types in schedule order (first occurrence wins), then every
    /// other type in its existing order. For putting the main services first.
    static func scheduleFirst(_ types: [String], schedule: [String]) -> [String] {
        let present = Dictionary(types.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let main = schedule.compactMap { present[$0.lowercased()] }.filter { seen.insert($0.lowercased()).inserted }
        return main + types.filter { !seen.contains($0.lowercased()) }
    }

    // MARK: Presets

    struct PresetItem {
        let name: String
        let serviceType: String
        let rule: Rule
        var note: String? = nil
    }

    struct Preset: Identifiable {
        let name: String
        let items: [PresetItem]
        var id: String { name }
    }

    static let presets = [acuraRSX]

    /// 2002–2006 Acura RSX owner's manual, normal conditions, automatic
    /// transmission. The manual's months row puts 12 months at 20,000 mi (6
    /// months per 10,000 mi).
    static let acuraRSX = Preset(name: "2002–06 Acura RSX", items: [
        .init(name: "Check engine oil and coolant", serviceType: "Fluids", rule: .init(),
              note: "At each fuel stop"),
        .init(name: "Replace engine oil", serviceType: "Oil change",
              rule: .init(everyMiles: 10_000, everyMonths: 6)),
        .init(name: "Rotate tires", serviceType: "Tire rotation",
              rule: .init(everyMiles: 10_000, everyMonths: 6),
              note: "Check tire inflation and condition at least once a month"),
        .init(name: "Replace engine oil filter", serviceType: "Oil change",
              rule: .init(everyMiles: 20_000, everyMonths: 12)),
        .init(name: "Inspect front and rear brakes", serviceType: "Inspection",
              rule: .init(everyMiles: 20_000, everyMonths: 12)),
        .init(name: "Check parking brake adjustment", serviceType: "Inspection",
              rule: .init(everyMiles: 20_000, everyMonths: 12)),
        .init(name: "Visual inspection", serviceType: "Inspection",
              rule: .init(everyMiles: 20_000, everyMonths: 12),
              note: "Tie rod ends, steering gear box and boots, suspension, driveshaft boots, brake hoses and lines, fluid levels, exhaust, fuel lines"),
        .init(name: "Inspect and adjust drive belts", serviceType: "Drive belts",
              rule: .init(everyMiles: 30_000, everyMonths: 18)),
        .init(name: "Replace dust and pollen filter", serviceType: "Cabin air filter",
              rule: .init(everyMiles: 30_000, everyMonths: 18)),
        .init(name: "Replace transmission fluid", serviceType: "Transmission fluid",
              rule: .init(everyMiles: 90_000, everyMonths: 60, firstMiles: 120_000, firstMonths: 72)),
        .init(name: "Replace air cleaner element", serviceType: "Air filter",
              rule: .init(everyMiles: 30_000)),
        .init(name: "Replace spark plugs", serviceType: "Spark plugs",
              rule: .init(everyMiles: 110_000)),
        .init(name: "Inspect valve clearance", serviceType: "Valve clearance",
              rule: .init(everyMiles: 110_000), note: "Otherwise adjust only if noisy"),
        .init(name: "Inspect idle speed", serviceType: "Idle speed",
              rule: .init(everyMiles: 160_000, everyMonths: 96)),
        .init(name: "Replace engine coolant", serviceType: "Coolant",
              rule: .init(everyMiles: 60_000, everyMonths: 60, firstMiles: 120_000, firstMonths: 120)),
        .init(name: "Replace brake fluid", serviceType: "Brake fluid",
              rule: .init(everyMonths: 36), note: "Independent of mileage"),
    ])
}

// MARK: - Vehicle bridge

extension Vehicle {
    var sortedScheduleItems: [ScheduleItem] {
        (scheduleItems ?? []).sorted { $0.order < $1.order }
    }

    func scheduleProgress(for item: ScheduleItem, today: Date = Date()) -> FactorySchedule.Progress? {
        let records = (maintenanceEntries ?? []).map { ($0.serviceType, $0.odometer, $0.date) }
        return FactorySchedule.progress(
            for: item.effectiveRule,
            lastDone: FactorySchedule.lastDone(item.serviceType, in: records),
            currentOdometer: currentOdometer,
            today: today
        )
    }

    /// Adds a preset's items after any already on the schedule.
    /// Every logged service that counts for this item, newest first.
    func entries(for item: ScheduleItem) -> [MaintenanceEntry] {
        (maintenanceEntries ?? [])
            .filter { $0.serviceType.caseInsensitiveCompare(item.serviceType) == .orderedSame }
            .sorted { ($0.date, $0.odometer) > ($1.date, $1.odometer) }
    }

    func loadSchedule(_ preset: FactorySchedule.Preset, into context: ModelContext) {
        let start = (scheduleItems ?? []).map(\.order).max().map { $0 + 1 } ?? 0
        for (offset, spec) in preset.items.enumerated() {
            let item = ScheduleItem(name: spec.name, serviceType: spec.serviceType, rule: spec.rule,
                                    note: spec.note, order: start + offset)
            context.insert(item)
            item.vehicle = self
        }
    }
}

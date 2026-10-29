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

    /// Car-specific schedules that can be loaded from the menu.
    static let presets = [acuraRSX]

    static let standardSource = "standard"
    static let manualSource = "manual"

    // MARK: Standard schedules

    /// Generic routine intervals change with how new the car is, because
    /// the parts and fluids changed: synthetic oil, oil-life monitors,
    /// iridium plugs and long-life coolant became standard around 2008, and
    /// 0W-16/0W-20 oil with 10,000 mi intervals and timing chains around 2018.
    enum Era: String, CaseIterable {
        case before2008, from2008, from2018

        /// The era for a model year; the middle one when it isn't known.
        init(year: Int?) {
            switch year {
            case .some(let y) where y < 2008: self = .before2008
            case .some(let y) where y >= 2018: self = .from2018
            default: self = .from2008
            }
        }

        var label: String {
            switch self {
            case .before2008: "cars from before 2008"
            case .from2008: "2008–2017 cars"
            case .from2018: "2018 and newer cars"
            }
        }
    }

    /// The standard schedule for a car of this model year.
    static func standard(forYear year: Int?) -> Preset { standard(for: Era(year: year)) }

    /// Routine intervals that keep almost any car of that era in good
    /// shape, on the careful side of what automakers list for normal
    /// driving. Each item can be changed to match the car's own schedule,
    /// or removed if it doesn't apply.
    static func standard(for era: Era) -> Preset {
        let older = era == .before2008
        let newest = era == .from2018
        var items: [PresetItem] = [
            .init(name: "Check oil level and tire pressure", serviceType: "Fluids", rule: .init(),
                  note: "Once a month and before long trips, including the spare"),
        ]
        switch era {
        case .before2008:
            items.append(.init(name: "Change engine oil and filter", serviceType: "Oil change",
                               rule: .init(everyMiles: 5_000, everyMonths: 6),
                               note: "With synthetic oil, 7,500 mi is fine. Older engines can use a little oil, so check the level monthly"))
        case .from2008:
            items.append(.init(name: "Change engine oil and filter", serviceType: "Oil change",
                               rule: .init(everyMiles: 7_500, everyMonths: 12),
                               note: "Synthetic oil. If the car has an oil-life reading, change it when that says, if sooner"))
        case .from2018:
            items.append(.init(name: "Change engine oil and filter", serviceType: "Oil change",
                               rule: .init(everyMiles: 10_000, everyMonths: 12),
                               note: "Follow the oil-life reading if sooner. Mostly short trips, towing or dusty roads: every 5,000 mi"))
        }
        items += [
            .init(name: "Rotate tires", serviceType: "Tire rotation",
                  rule: older ? .init(everyMiles: 5_000, everyMonths: 6) : .init(everyMiles: 7_500, everyMonths: 12),
                  note: "Easy to do with each oil change"),
            .init(name: "Inspect brakes, suspension, belts, hoses and fluids", serviceType: "Inspection",
                  rule: older ? .init(everyMiles: 5_000, everyMonths: 6) : .init(everyMiles: 10_000, everyMonths: 12),
                  note: older
                    ? "Rubber and suspension parts wear with age: brake pads and rotors, bushings, CV boots, belts, hoses, exhaust, lights"
                    : "Brake pads and rotors, steering and suspension parts, CV boots, exhaust, lights. Check the alignment if the car pulls"),
            .init(name: "Replace wiper blades", serviceType: "Wiper blades",
                  rule: .init(everyMonths: 12)),
            .init(name: "Replace cabin air filter", serviceType: "Cabin air filter",
                  rule: .init(everyMiles: 15_000, everyMonths: 12),
                  note: older ? "If the car has one; many from before 2000 don't" : nil),
            .init(name: "Replace engine air filter", serviceType: "Air filter",
                  rule: .init(everyMiles: 30_000, everyMonths: 36),
                  note: "Sooner on dusty roads"),
        ]
        if older {
            items.append(.init(name: "Replace fuel filter", serviceType: "Fuel filter",
                               rule: .init(everyMiles: 30_000),
                               note: "If it's a separate part; some are built into the fuel pump in the tank"))
        }
        items += [
            .init(name: "Test battery", serviceType: "Battery",
                  rule: .init(everyMonths: 12, firstMonths: 36),
                  note: "Yearly once it's 3 years old; most last 3–5 years"),
            .init(name: "Replace brake fluid", serviceType: "Brake fluid",
                  rule: .init(everyMonths: 36),
                  note: "By time, not miles: it absorbs water. Some makers say every 2 years"),
            .init(name: "Replace transmission fluid", serviceType: "Transmission fluid",
                  rule: older ? .init(everyMiles: 30_000, everyMonths: 36) : .init(everyMiles: 60_000, everyMonths: 60),
                  note: newest
                    ? "Even when the manual says \"lifetime\". CVTs often need it every 25,000–50,000 mi"
                    : "Even when the manual says \"lifetime\", changing it is cheap insurance"),
            .init(name: "Replace differential and transfer case fluid", serviceType: "Differential fluid",
                  rule: .init(everyMiles: 60_000, everyMonths: 60),
                  note: "All-wheel, four-wheel and rear-wheel drive cars. Remove this for front-wheel drive"),
            older
                ? .init(name: "Replace engine coolant", serviceType: "Coolant",
                        rule: .init(everyMiles: 60_000, everyMonths: 60),
                        note: "Older green coolant: every 30,000 mi or 2 years")
                : .init(name: "Replace engine coolant", serviceType: "Coolant",
                        rule: .init(everyMiles: 50_000, everyMonths: 60, firstMiles: 100_000, firstMonths: 120),
                        note: "Long-life coolant: first at 100,000 mi or 10 years, then every 50,000 mi or 5 years"),
            .init(name: "Replace spark plugs", serviceType: "Spark plugs",
                  rule: .init(everyMiles: older ? 60_000 : 100_000),
                  note: older ? "Iridium plugs last 100,000 mi; copper ones 30,000" : "Electric cars: remove this"),
        ]
        if !newest {
            items.append(.init(name: "Replace timing belt", serviceType: "Timing belt",
                               rule: .init(everyMiles: older ? 90_000 : 100_000, everyMonths: 84),
                               note: "Only if the engine has a belt; many have a chain that lasts the life of the car. Remove this if yours does"))
        }
        return Preset(name: "Standard schedule", items: items)
    }

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

    /// Replaces the schedule with `items` (the standard one or a preset).
    func replaceSchedule(with items: [FactorySchedule.PresetItem], source: String?, in context: ModelContext) {
        for old in scheduleItems ?? [] { context.delete(old) }
        scheduleItems = []
        loadSchedule(FactorySchedule.Preset(name: source ?? "", items: items), into: context)
        scheduleSource = source
    }

    /// The car is on the standard schedule (shows a note that it can be
    /// changed to match the car).
    var hasStandardSchedule: Bool {
        scheduleSource == FactorySchedule.standardSource && !(scheduleItems ?? []).isEmpty
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

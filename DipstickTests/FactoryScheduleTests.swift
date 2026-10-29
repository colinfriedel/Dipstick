//
//  FactoryScheduleTests.swift
//  DipstickTests
//

import Foundation
import SwiftData
import Testing
@testable import Dipstick

@MainActor
struct FactoryScheduleTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func progress(_ rule: FactorySchedule.Rule, last: (Int, Date)?, odometer: Int, today: Date)
        -> FactorySchedule.Progress? {
        FactorySchedule.progress(for: rule, lastDone: last.map { .init(odometer: $0.0, date: $0.1) },
                                 currentOdometer: odometer, today: today, calendar: calendar)
    }

    @Test func milesFromLastService() throws {
        let p = try #require(progress(.init(everyMiles: 10_000, everyMonths: 6),
                                      last: (50_000, date(2026, 9, 1)), odometer: 52_500, today: date(2026, 10, 1)))
        #expect(p.due.odometer == 60_000)
        #expect(p.due.date == date(2027, 3, 1))
        #expect(p.milesLeft == 7_500)
        #expect(p.status == .ok)
        // 25% of the miles, 30 of 181 days: the miles side is further along.
        #expect(p.fraction == 0.25)
        #expect(!p.needsRecord)
    }

    @Test func timeOnlyItemUsesTheCalendar() throws {
        let p = try #require(progress(.init(everyMonths: 36), last: (56_696, date(2026, 10, 17)),
                                      odometer: 56_696, today: date(2028, 4, 17)))
        #expect(p.due.date == date(2029, 10, 17))
        #expect(p.due.odometer == nil)
        #expect(abs((p.fraction ?? 0) - 0.5) < 0.01)
    }

    @Test func overdueWhenPastEitherLimit() throws {
        let p = try #require(progress(.init(everyMiles: 10_000, everyMonths: 6),
                                      last: (50_000, date(2025, 1, 1)), odometer: 51_000, today: date(2026, 1, 1)))
        #expect(p.status == .overdue)
        #expect((p.fraction ?? 0) > 1)
    }

    @Test func neverLoggedCountsFromNewTowardFirstInterval() throws {
        let rule = FactorySchedule.Rule(everyMiles: 60_000, everyMonths: 60, firstMiles: 120_000, firstMonths: 120)
        let p = try #require(progress(rule, last: nil, odometer: 60_000, today: date(2026, 10, 1)))
        #expect(p.due.odometer == 120_000)
        #expect(p.fraction == 0.5)
        #expect(!p.needsRecord)
        // Once logged, the regular interval takes over.
        let after = try #require(progress(rule, last: (120_000, date(2030, 1, 1)), odometer: 120_000, today: date(2030, 1, 1)))
        #expect(after.due.odometer == 180_000)
    }

    @Test func neverLoggedAndPastDueOrTimeOnlyNeedsARecord() throws {
        let belts = try #require(progress(.init(everyMiles: 30_000), last: nil, odometer: 56_000, today: date(2026, 10, 1)))
        #expect(belts.needsRecord)
        let fluid = try #require(progress(.init(everyMonths: 36), last: nil, odometer: 56_000, today: date(2026, 10, 1)))
        #expect(fluid.needsRecord)
    }

    @Test func noIntervalIsNotTracked() {
        #expect(progress(.init(), last: nil, odometer: 1, today: date(2026, 1, 1)) == nil)
    }

    @Test func summaries() {
        #expect(FactorySchedule.Rule(everyMiles: 10_000, everyMonths: 6).summary == "Every 10,000 mi or 6 mo")
        #expect(FactorySchedule.Rule(everyMonths: 36).summary == "Every 3 yr")
        #expect(FactorySchedule.Rule(everyMiles: 60_000, everyMonths: 60, firstMiles: 120_000, firstMonths: 120).summary
                == "At 120,000 mi or 10 yr, then every 60,000 mi or 5 yr")
        #expect(FactorySchedule.Rule().summary == nil)
    }

    @Test func lastDoneMatchesTypeIgnoringCase() {
        let records = [("Oil change", 50_000, date(2026, 1, 1)), ("oil change", 55_000, date(2026, 7, 1)),
                       ("Tire rotation", 56_000, date(2026, 8, 1))]
        #expect(FactorySchedule.lastDone("OIL CHANGE", in: records)
                == .init(odometer: 55_000, date: date(2026, 7, 1)))
        #expect(FactorySchedule.lastDone("Coolant", in: records) == nil)
    }

    @Test func scheduledTypesComeFirstInScheduleOrder() {
        let byRecency = ["Brake fluid", "Inspection", "Headlight upgrade", "Oil change", "Tire rotation"]
        let schedule = ["Fluids", "Oil change", "Tire rotation", "Oil change", "Inspection", "Brake fluid"]
        #expect(FactorySchedule.scheduleFirst(byRecency, schedule: schedule)
                == ["Oil change", "Tire rotation", "Inspection", "Brake fluid", "Headlight upgrade"])
        #expect(FactorySchedule.scheduleFirst(byRecency, schedule: []) == byRecency)
    }

    @Test func rsxPresetCoversTheManual() {
        let items = FactorySchedule.acuraRSX.items
        #expect(items.count == 16)
        #expect(items.first { $0.name == "Replace brake fluid" }?.rule == .init(everyMonths: 36))
        #expect(items.filter { !$0.rule.isTracked }.map(\.name) == ["Check engine oil and coolant"])
    }

    @Test func yourIntervalReplacesTheFactoryOneFieldByField() {
        let oil = ScheduleItem(name: "Replace engine oil", serviceType: "Oil change",
                               rule: .init(everyMiles: 10_000, everyMonths: 6))
        #expect(!oil.hasCustomInterval)
        #expect(oil.effectiveRule == oil.rule)
        oil.customEveryMiles = 5_000
        #expect(oil.effectiveRule == .init(everyMiles: 5_000, everyMonths: 6))
        #expect(oil.rule == .init(everyMiles: 10_000, everyMonths: 6))
    }

    @MainActor
    @Test func historyIsThisItemsServicesNewestFirst() throws {
        let context = ModelContext(try ModelContainer(for: Vehicle.self,
                                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let car = Vehicle(name: "Acura")
        context.insert(car)
        for (type, odometer, day) in [("Oil change", 50_000, 1), ("oil change", 55_000, 2), ("Tire rotation", 55_000, 2)] {
            let entry = MaintenanceEntry(date: date(2026, 1, day), odometer: odometer, serviceType: type)
            context.insert(entry)
            entry.vehicle = car
        }
        let item = ScheduleItem(name: "Replace engine oil", serviceType: "Oil change")
        #expect(car.entries(for: item).map(\.odometer) == [55_000, 50_000])
    }

    @MainActor
    @Test func loadingAPresetAppendsInOrderAndCascades() throws {
        let context = ModelContext(try ModelContainer(for: Vehicle.self,
                                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let car = Vehicle(name: "Acura")
        context.insert(car)
        car.loadSchedule(FactorySchedule.acuraRSX, into: context)
        car.loadSchedule(FactorySchedule.acuraRSX, into: context)
        #expect(car.sortedScheduleItems.map(\.order) == Array(0..<32))
        #expect(car.sortedScheduleItems.first?.name == "Check engine oil and coolant")
        context.delete(car)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<ScheduleItem>()) == 0)
    }
}

@MainActor
struct StandardScheduleTests {
    @Test(arguments: FactorySchedule.Era.allCases)
    func everyStandardItemIsTrackedOrANote(era: FactorySchedule.Era) {
        let items = FactorySchedule.standard(for: era).items
        #expect(items.count >= 12)
        // Only the monthly check has no interval; it's a reminder.
        #expect(items.filter { !$0.rule.isTracked }.map(\.serviceType) == ["Fluids"])
        #expect(Set(items.map(\.name)).count == items.count)
        // A brand-new car isn't overdue for anything.
        for item in items where item.rule.isTracked {
            let progress = FactorySchedule.progress(for: item.rule, lastDone: nil, currentOdometer: 0)
            #expect(progress?.status == .ok, "\(item.name)")
        }
    }

    @Test func newCarsStartOnTheStandardScheduleAndAPresetReplacesIt() throws {
        let context = ModelContext(try ModelContainer(for: Vehicle.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let car = Vehicle(name: "Civic")
        context.insert(car)
        car.loadSchedule(FactorySchedule.standard(forYear: 2019), into: context)
        car.scheduleSource = FactorySchedule.standardSource
        #expect(car.hasStandardSchedule)

        car.replaceSchedule(with: FactorySchedule.acuraRSX.items, source: FactorySchedule.acuraRSX.name, in: context)
        context.saveNow()
        #expect(!car.hasStandardSchedule)
        #expect(car.sortedScheduleItems.count == FactorySchedule.acuraRSX.items.count)
        #expect(try context.fetchCount(FetchDescriptor<ScheduleItem>()) == FactorySchedule.acuraRSX.items.count)
    }

    @Test func theYearPicksTheSchedule() {
        #expect(FactorySchedule.Era(year: 2003) == .before2008)
        #expect(FactorySchedule.Era(year: 2008) == .from2008)
        #expect(FactorySchedule.Era(year: 2017) == .from2008)
        #expect(FactorySchedule.Era(year: 2018) == .from2018)
        #expect(FactorySchedule.Era(year: nil) == .from2008)
        func oil(_ year: Int?) -> FactorySchedule.Rule? {
            FactorySchedule.standard(forYear: year).items.first { $0.serviceType == "Oil change" }?.rule
        }
        #expect(oil(2003)?.everyMiles == 5_000)
        #expect(oil(2012)?.everyMiles == 7_500)
        #expect(oil(2024)?.everyMiles == 10_000)
        let types = { (year: Int) in Set(FactorySchedule.standard(forYear: year).items.map(\.serviceType)) }
        #expect(types(2003).contains("Fuel filter") && types(2003).contains("Timing belt"))
        #expect(!types(2024).contains("Timing belt") && !types(2024).contains("Fuel filter"))
    }
}

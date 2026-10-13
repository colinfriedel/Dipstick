//
//  MaintenanceDueTests.swift
//  DipstickTests
//

import Foundation
import Testing
@testable import Dipstick

@MainActor
struct MaintenanceDueTests {
    private typealias Calc = MaintenanceDueCalculator

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var today: Date { date(2026, 10, 12) }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func record(
        _ id: String, _ type: String = "Oil change",
        on day: Date? = nil, dueMiles: Int? = nil, dueDate: Date? = nil
    ) -> Calc.Record<String> {
        Calc.Record(
            id: id, serviceType: type, date: day ?? date(2026, 4, 12), odometer: 0,
            due: .init(odometer: dueMiles, date: dueDate)
        )
    }

    private func items(_ records: [Calc.Record<String>], odometer: Int = 50_000) -> [Calc.Item<String>] {
        Calc.items(for: records, currentOdometer: odometer, today: today, calendar: calendar)
    }

    @Test func okWhenFarAway() {
        let item = items([record("a", dueMiles: 55_000, dueDate: date(2027, 4, 12))]).first
        #expect(item?.status == .ok)
        #expect(item?.milesLeft == 5_000)
    }

    @Test func dueSoonByMiles() {
        let item = items([record("a", dueMiles: 50_800)]).first
        #expect(item?.status == .dueSoon)
        #expect(item?.summary == "due in 800 mi")
    }

    @Test func dueSoonByDate() {
        let item = items([record("a", dueDate: date(2026, 11, 1))]).first
        #expect(item?.status == .dueSoon)
        #expect(item?.daysLeft == 20)
        #expect(item?.summary == "due in 20 days")
    }

    @Test func overdueByMiles() {
        let item = items([record("a", dueMiles: 49_680)]).first
        #expect(item?.status == .overdue)
        #expect(item?.summary == "overdue by 320 mi")
    }

    @Test func overdueByDate() {
        let item = items([record("a", dueDate: date(2026, 10, 9))]).first
        #expect(item?.status == .overdue)
        #expect(item?.summary == "overdue by 3 days")
    }

    @Test func worseOfMilesAndDateWins() {
        // Fine on miles, overdue by date.
        let item = items([record("a", dueMiles: 54_000, dueDate: date(2026, 10, 1))]).first
        #expect(item?.status == .overdue)
        #expect(item?.summary == "overdue by 11 days")
    }

    @Test func boundariesCountAsDueSoon() {
        #expect(items([record("a", dueMiles: 51_000)]).first?.status == .dueSoon)
        #expect(items([record("a", dueMiles: 51_001)]).first?.status == .ok)
        #expect(items([record("a", dueMiles: 50_000)]).first?.summary == "due now")
        #expect(items([record("a", dueDate: today)]).first?.summary == "due today")
    }

    @Test func onlyLatestRecordPerTypeCounts() {
        let result = items([
            record("old", on: date(2026, 1, 1), dueMiles: 45_000),        // would be overdue
            record("new", on: date(2026, 9, 1), dueMiles: 55_000),        // replaces it
        ])
        #expect(result.count == 1)
        #expect(result.first?.id == "new")
        #expect(result.first?.status == .ok)
    }

    @Test func latestWithoutNextDueStopsTracking() {
        let result = items([
            record("old", on: date(2026, 1, 1), dueMiles: 45_000),
            record("new", on: date(2026, 9, 1)),
        ])
        #expect(result.isEmpty)
    }

    @Test func serviceTypesMatchIgnoringCase() {
        let result = items([
            record("old", "oil change", on: date(2026, 1, 1), dueMiles: 45_000),
            record("new", "Oil change", on: date(2026, 9, 1), dueMiles: 55_000),
        ])
        #expect(result.map(\.id) == ["new"])
    }

    @Test func sortedMostUrgentFirst() {
        let result = items([
            record("ok", "Air filter", dueMiles: 60_000),
            record("soon", "Tire rotation", dueMiles: 50_900),
            record("soonest", "Coolant", dueDate: date(2026, 10, 15)),
            record("late", "Oil change", dueMiles: 49_000),
        ])
        #expect(result.map(\.id) == ["late", "soonest", "soon", "ok"])
    }

    @Test func noRecordsMeansNothingDue() {
        #expect(items([]).isEmpty)
    }
}

@MainActor
struct LatestMPGTests {
    @Test func latestIsMostRecentFullTankByOdometer() {
        typealias Fill = MPGCalculator.Fill<String>
        let fills = [
            Fill(id: "a", odometer: 1_000, gallons: 10, isFullTank: true),
            Fill(id: "b", odometer: 1_300, gallons: 10, isFullTank: true),  // 30 mpg
            Fill(id: "c", odometer: 1_500, gallons: 10, isFullTank: true),  // 20 mpg
            Fill(id: "p", odometer: 1_600, gallons: 3, isFullTank: false),  // partial, no MPG yet
        ]
        let results = MPGCalculator.results(for: fills)
        #expect(MPGCalculator.latest(in: fills, results: results)?.mpg == 20)
        #expect(MPGCalculator.latest(in: [fills[0]], results: [:]) == nil)
    }
}

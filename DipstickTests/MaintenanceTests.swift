//
//  MaintenanceTests.swift
//  DipstickTests
//

import Foundation
import Testing
import SwiftData
@testable import Dipstick

@MainActor
struct MaintenanceScheduleTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func nextDueAddsMilesAndMonths() {
        let due = MaintenanceSchedule.nextDue(
            odometer: 56_400, date: date(2026, 4, 12),
            every: .init(miles: 5_000, months: 6), calendar: calendar
        )
        #expect(due.odometer == 61_400)
        #expect(due.date == date(2026, 10, 12))
    }

    @Test func emptyIntervalHasNothingDue() {
        let due = MaintenanceSchedule.nextDue(
            odometer: 56_400, date: date(2026, 4, 12), every: .init(), calendar: calendar
        )
        #expect(due == .init(odometer: nil, date: nil))
        #expect(due.summary == nil)
    }

    @Test func intervalRoundTrips() {
        let start = date(2026, 4, 12)
        let interval = MaintenanceSchedule.Interval(miles: 3_000, months: 4)
        let due = MaintenanceSchedule.nextDue(odometer: 10_000, date: start, every: interval, calendar: calendar)
        #expect(MaintenanceSchedule.interval(odometer: 10_000, date: start, due: due, calendar: calendar) == interval)
    }

    @Test func intervalRoundTripsAtEndOfMonth() {
        // Jan 31 + 1 month = Feb 28; that must still read back as 1 month.
        let start = date(2026, 1, 31)
        let due = MaintenanceSchedule.nextDue(
            odometer: 0, date: start, every: .init(months: 1), calendar: calendar
        )
        #expect(due.date == date(2026, 2, 28))
        #expect(MaintenanceSchedule.interval(odometer: 0, date: start, due: due, calendar: calendar).months == 1)
    }
}

@MainActor
struct ServiceTypeTests {
    @Test func customNamesFollowBuiltInsWithoutDuplicates() {
        let options = ServiceType.options(addingUsed: [
            "Clutch slave cylinder", "oil change", "  ", "clutch slave cylinder", "Alignment",
        ])
        #expect(options.prefix(ServiceType.builtIn.count).elementsEqual(ServiceType.builtIn))
        #expect(Array(options.dropFirst(ServiceType.builtIn.count)) == ["Alignment", "Clutch slave cylinder"])
    }
}

@MainActor
struct MaintenanceSearchTests {
    private func matches(_ query: String, type: String? = nil) -> Bool {
        MaintenanceSearch.matches(
            serviceType: "Oil change",
            notes: "Used Mobil 1 5W-30",
            partNames: ["Oil filter", "Drain plug gasket"],
            query: query,
            typeFilter: type
        )
    }

    @Test func emptyQueryMatchesEverything() {
        #expect(matches(""))
        #expect(matches("   "))
    }

    @Test func searchesTypeNotesAndPartsIgnoringCase() {
        #expect(matches("OIL"))
        #expect(matches("mobil"))
        #expect(matches("gasket"))
        #expect(!matches("brake"))
    }

    @Test func everyWordMustMatchSomewhere() {
        #expect(matches("mobil gasket"))
        #expect(!matches("mobil brake"))
    }

    @Test func typeFilterIsExactIgnoringCase() {
        #expect(matches("", type: "oil change"))
        #expect(!matches("", type: "Tire rotation"))
    }
}

@MainActor
struct MaintenanceModelTests {
    @Test func deletingVehicleDeletesEntriesAndParts() throws {
        let container = try ModelContainer(
            for: Vehicle.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let vehicle = Vehicle(name: "Project Car")
        context.insert(vehicle)
        let entry = MaintenanceEntry(odometer: 1_000, serviceType: "Oil change", cost: 40)
        context.insert(entry)
        entry.vehicle = vehicle
        let part = PartUsed(name: "Oil filter", cost: 9)
        context.insert(part)
        part.entry = entry
        try context.save()
        #expect(vehicle.maintenanceEntries?.first?.parts?.count == 1)

        context.delete(vehicle)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<MaintenanceEntry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PartUsed>()) == 0)
    }
}

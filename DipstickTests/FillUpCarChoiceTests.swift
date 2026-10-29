//
//  FillUpCarChoiceTests.swift
//  DipstickTests
//

import Foundation
import SwiftData
import Testing
@testable import Dipstick

@MainActor
struct FillUpCarChoiceTests {
    @Test func connectedCarFirstThenMostRecentlyUsed() throws {
        let context = ModelContext(try ModelContainer(for: Vehicle.self,
                                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let day = { (d: Int) in Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: d))! }
        let acura = Vehicle(name: "Acura"), civic = Vehicle(name: "Civic"), truck = Vehicle(name: "Truck")
        for car in [acura, civic, truck] { context.insert(car) }

        let fill = FuelEntry(date: day(10), odometer: 1, gallons: 10, totalCost: 30)
        context.insert(fill)
        fill.vehicle = acura
        let drive = Trip(startDate: day(20), endDate: day(20), cityMiles: 5, highwayMiles: 0, status: .assigned)
        context.insert(drive)
        drive.vehicle = civic
        // A ride in someone else's car doesn't count.
        let ride = Trip(startDate: day(25), endDate: day(25), cityMiles: 5, highwayMiles: 0, status: .notMine)
        context.insert(ride)
        ride.vehicle = acura

        #expect(Vehicle.orderedForFillUp([acura, civic, truck]).map(\.name) == ["Civic", "Acura", "Truck"])
        #expect(Vehicle.orderedForFillUp([acura, civic, truck], connected: truck).map(\.name) == ["Truck", "Civic", "Acura"])
    }
}

@MainActor
struct CarDirectoryTests {
    @Test func eachCarHasItsOwnStableID() throws {
        let context = ModelContext(try ModelContainer(for: Vehicle.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let a = Vehicle(name: "Acura"), b = Vehicle(name: "Lexus")
        context.insert(a)
        context.insert(b)
        try context.save()
        // The same every time (the encoder's field order isn't fixed on its own).
        #expect(Set((0..<20).map { _ in a.directoryID }).count == 1)
        #expect(a.directoryID != b.directoryID)
        let fetched = try context.fetch(FetchDescriptor<Vehicle>()).first { $0.name == "Acura" }
        #expect(fetched?.directoryID == a.directoryID)
    }
}

struct FillUpLinkTests {
    @Test func linksRoundTripTheCar() throws {
        let id = "eyJpbXBsZW1lbnRhdGlvbiI6+/="
        let url = CarDirectory.fillUpURL(carID: id)
        #expect(url.absoluteString.hasPrefix("dipstick://fillup?car="))
        let parsed = try #require(CarDirectory.carID(inFillUpURL: url))
        #expect(parsed == id)
        let ask = try #require(CarDirectory.carID(inFillUpURL: CarDirectory.fillUpURL(carID: nil)))
        #expect(ask == nil)
        #expect(CarDirectory.carID(inFillUpURL: URL(string: "dipstick://backup")!) == nil)
        #expect(CarDirectory.carID(inFillUpURL: URL(string: "https://fillup")!) == nil)
    }
}

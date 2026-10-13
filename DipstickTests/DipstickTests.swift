//
//  DipstickTests.swift
//  DipstickTests
//
//  Created by Colin Friedel on 10/12/26.
//

import Foundation
import Testing
import SwiftData
@testable import Dipstick

@MainActor
struct VehicleTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Vehicle.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func insertFetchAndDelete() throws {
        let context = try makeContext()
        context.insert(Vehicle(name: "Daily Driver", currentOdometer: 48_210))
        context.insert(Vehicle(name: "Project Car", currentOdometer: 131_870))

        let sorted = try context.fetch(FetchDescriptor<Vehicle>(sortBy: [SortDescriptor(\.name)]))
        #expect(sorted.map(\.name) == ["Daily Driver", "Project Car"])

        context.delete(sorted[0])
        #expect(try context.fetchCount(FetchDescriptor<Vehicle>()) == 1)
    }

    @Test func deletingVehicleDeletesItsFuelEntries() throws {
        let context = try makeContext()
        let vehicle = Vehicle(name: "Daily Driver")
        context.insert(vehicle)
        let entry = FuelEntry(odometer: 1_000, gallons: 10, totalCost: 35)
        context.insert(entry)
        entry.vehicle = vehicle
        try context.save()
        #expect(vehicle.fuelEntries?.count == 1)

        context.delete(vehicle)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<FuelEntry>()) == 0)
    }

    @Test func recordOdometerOnlyMovesForward() {
        let vehicle = Vehicle(name: "A", currentOdometer: 50_000)
        vehicle.recordOdometer(49_000)
        #expect(vehicle.currentOdometer == 50_000)
        vehicle.recordOdometer(50_350)
        #expect(vehicle.currentOdometer == 50_350)
    }

    @Test func yearMakeModelSkipsMissingParts() {
        #expect(Vehicle(name: "A", year: 1994, make: "Mazda", model: "Miata").yearMakeModel == "1994 Mazda Miata")
        #expect(Vehicle(name: "B", make: "Mazda").yearMakeModel == "Mazda")
        #expect(Vehicle(name: "C").yearMakeModel == "")
    }
}

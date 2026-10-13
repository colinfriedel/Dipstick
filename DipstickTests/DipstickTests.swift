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

    @Test func yearMakeModelSkipsMissingParts() {
        #expect(Vehicle(name: "A", year: 1994, make: "Mazda", model: "Miata").yearMakeModel == "1994 Mazda Miata")
        #expect(Vehicle(name: "B", make: "Mazda").yearMakeModel == "Mazda")
        #expect(Vehicle(name: "C").yearMakeModel == "")
    }
}

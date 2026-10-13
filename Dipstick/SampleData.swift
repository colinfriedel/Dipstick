//
//  SampleData.swift
//  Dipstick
//

#if DEBUG
import Foundation
import SwiftData

/// Debug-only test data. Launch with `-seedSampleData` (Xcode: Product >
/// Scheme > Edit Scheme > Arguments) to add a "Sample Car" with ~14 months of
/// fill-ups, so the stats and charts have something to show.
enum SampleData {
    static let launchArgument = "-seedSampleData"

    @MainActor
    static func seedIfRequested(into context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }
        let existing = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
        guard !existing.contains(where: { $0.name == "Sample Car" }) else { return }

        let vehicle = Vehicle(name: "Sample Car", year: 2019, make: "Honda", model: "Civic", currentOdometer: 0)
        context.insert(vehicle)

        let calendar = Calendar.current
        let start = calendar.date(byAdding: .month, value: -14, to: Date())!
        var generator = SeededGenerator(seed: 42)
        var odometer = 41_200
        var date = start

        while date < Date() {
            let miles = Int.random(in: 250...360, using: &generator)
            let mpg = Double.random(in: 27...35, using: &generator)
            let price = Double.random(in: 3.15...3.95, using: &generator)
            let isPartial = Int.random(in: 0..<10, using: &generator) == 0
            odometer += miles
            let gallons = (Double(miles) / mpg * 1000).rounded() / 1000
            let entry = FuelEntry(
                date: date, odometer: odometer, gallons: gallons,
                totalCost: (gallons * price * 100).rounded() / 100,
                isFullTank: !isPartial
            )
            context.insert(entry)
            entry.vehicle = vehicle
            date = calendar.date(byAdding: .day, value: Int.random(in: 9...16, using: &generator), to: date)!
        }
        vehicle.recordOdometer(odometer)
    }
}

/// Same numbers every run, so the sample charts look the same each time.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
#endif

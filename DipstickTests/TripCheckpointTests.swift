//
//  TripCheckpointTests.swift
//  DipstickTests
//

import Foundation
import Testing
import SwiftData
@testable import Dipstick

@MainActor
struct TripCheckpointTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    /// One sample per second heading north at `mph` for `seconds`.
    private func samples(mph: Double, seconds: Int, from time: Date, latitude: Double = 37) -> [TripClassifier.Sample] {
        let metersPerSecond = mph / TripClassifier.mphPerMetersPerSecond
        return (0...seconds).map { i in
            TripClassifier.Sample(timestamp: time + Double(i),
                                  latitude: latitude + Double(i) * metersPerSecond / 111_320,
                                  longitude: -122, speed: metersPerSecond, horizontalAccuracy: 5)
        }
    }

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Vehicle.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    @Test func recoversInterruptedTripForItsCar() throws {
        let context = try makeContext()
        let car = Vehicle(name: "Acura RSX")
        context.insert(car)
        try context.save()

        let drive = samples(mph: 60, seconds: 300, from: start)  // 5 mi
        let checkpoint = TripCheckpoint(
            startDate: start, vehicleID: car.persistentModelID,
            connectionName: "CarPlay (CarPlay)", connectionID: "1C:50:1E:B4:BC:F1",
            lastMoving: drive.last!.timestamp, samples: drive
        )
        // Survives being written to disk and read back.
        let decoded = try JSONDecoder().decode(TripCheckpoint.self, from: JSONEncoder().encode(checkpoint))

        let trip = try #require(decoded.recover(into: context))
        #expect(trip.vehicle?.persistentModelID == car.persistentModelID)
        #expect(trip.status == .assigned)
        #expect(abs(trip.totalMiles - 5) < 0.05)
        #expect(trip.connectionID == "1C:50:1E:B4:BC:F1")
    }

    @Test func trimsWalkingAfterLastDrivingSpeed() throws {
        let context = try makeContext()
        let drive = samples(mph: 30, seconds: 240, from: start)                     // 2 mi
        let walk = samples(mph: 15, seconds: 120, from: drive.last!.timestamp + 1, // would add 0.5 mi
                           latitude: drive.last!.latitude)
        let checkpoint = TripCheckpoint(startDate: start, vehicleID: nil, connectionName: nil, connectionID: nil,
                                        lastMoving: drive.last!.timestamp, samples: drive + walk)
        let trip = try #require(checkpoint.recover(into: context))
        #expect(abs(trip.totalMiles - 2) < 0.05)
        #expect(trip.status == .unreviewed)
    }

    @Test func tooShortCheckpointIsDropped() throws {
        let context = try makeContext()
        let blip = samples(mph: 10, seconds: 10, from: start)
        let checkpoint = TripCheckpoint(startDate: start, vehicleID: nil, connectionName: nil, connectionID: nil,
                                        lastMoving: blip.last!.timestamp, samples: blip)
        #expect(checkpoint.recover(into: context) == nil)
        #expect(try context.fetchCount(FetchDescriptor<Trip>()) == 0)
    }
}

//
//  TripFixesTests.swift
//  DipstickTests
//

import Foundation
import Testing
import SwiftData
@testable import Dipstick

@MainActor
struct VehicleConnectionTests {
    private let lexusCarPlay = CarConnection(name: "CarPlay (CarPlay)", id: "00:00:05:04:37:20")
    private let lexusBluetooth = CarConnection(name: "LEXUS ES (Bluetooth)", id: "AA:BB:CC:DD:EE:FF")

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Vehicle.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    @Test func existingSingleLinkCarriesOver() {
        let car = Vehicle(name: "Mom's Car")
        car.connectionID = lexusCarPlay.id
        car.connectionName = lexusCarPlay.name
        #expect(car.connections == [lexusCarPlay])
        #expect(car.knowsConnection(lexusCarPlay.id))
    }

    @Test func carCanHaveBluetoothAndCarPlay() {
        let car = Vehicle(name: "Mom's Car")
        car.connectionID = lexusCarPlay.id          // old single link
        car.addConnection(lexusBluetooth)
        car.addConnection(lexusBluetooth)           // duplicate ignored
        #expect(car.connections.map(\.id) == [lexusCarPlay.id, lexusBluetooth.id])
        #expect(car.connectionID == nil)            // folded into the list

        car.removeConnection(id: lexusCarPlay.id)
        #expect(car.connections == [lexusBluetooth])
    }

    @Test func matchingFindsTheCarByAnyOfItsConnections() throws {
        let context = try makeContext()
        let rsx = Vehicle(name: "Acura")
        rsx.addConnection(CarConnection(name: "CarPlay (CarPlay)", id: "1C:50:1E:B4:BC:F1"))
        let lexus = Vehicle(name: "Mom's Car")
        lexus.addConnection(lexusCarPlay)
        lexus.addConnection(lexusBluetooth)
        context.insert(rsx)
        context.insert(lexus)

        #expect(Vehicle.matching(lexusBluetooth, in: context)?.name == "Mom's Car")
        #expect(Vehicle.matching(lexusCarPlay, in: context)?.name == "Mom's Car")
        #expect(Vehicle.matching(CarConnection(name: "x", id: "1C:50:1E:B4:BC:F1"), in: context)?.name == "Acura")
        #expect(Vehicle.matching(CarConnection(name: "AirPods", id: "11:22:33"), in: context) == nil)
    }
}

@MainActor
struct NotYetDrivenTests {
    private typealias Rule = TripRecorder.AutoStop
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func warmingUpWithConnectionsSettlingDoesNotEndTheTrip() {
        // Five minutes in, never driven, Bluetooth handed over to CarPlay.
        #expect(!Rule.shouldStop(now: start + 300, lastMoving: start, hasDriven: false,
                                 connectionPresent: false, stopRequested: true))
    }

    @Test func neverDrivenTripEndsAfterTenMinutesDisconnected() {
        #expect(Rule.shouldStop(now: start + 600, lastMoving: start, hasDriven: false,
                                connectionPresent: false, stopRequested: false))
    }
}

@MainActor
struct TripContinuationTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let rsxCarPlay = CarConnection(name: "CarPlay (CarPlay)", id: "1C:50:1E:B4:BC:F1")

    private func split(_ city: Double, _ highway: Double) -> TripClassifier.Split {
        TripClassifier.Split(cityMiles: city, highwayMiles: highway)
    }

    private func makeContext() throws -> (ModelContext, Vehicle) {
        let context = ModelContext(try ModelContainer(for: Vehicle.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let car = Vehicle(name: "Acura")
        context.insert(car)
        return (context, car)
    }

    @Test func headUnitRebootAtALongLightGivesOneTrip() throws {
        let (context, car) = try makeContext()
        // First part ends at the light; reconnect and drive off 4 minutes later.
        let first = Trip.save(start: start, end: start + 900, split: split(3, 5),
                              vehicle: car, connection: rsxCarPlay, in: context)
        let second = Trip.save(start: start + 900 + 240, end: start + 2_000, split: split(2, 1),
                               vehicle: car, connection: rsxCarPlay, in: context)
        #expect(second.persistentModelID == first.persistentModelID)
        #expect(try context.fetchCount(FetchDescriptor<Trip>()) == 1)
        #expect(first.cityMiles == 5 && first.highwayMiles == 6)
        #expect(first.startDate == start && first.endDate == start + 2_000)
    }

    @Test func laterDriveIsASeparateTrip() throws {
        let (context, car) = try makeContext()
        Trip.save(start: start, end: start + 900, split: split(3, 5), vehicle: car, connection: rsxCarPlay, in: context)
        Trip.save(start: start + 900 + 3_600, end: start + 6_000, split: split(2, 1),
                  vehicle: car, connection: rsxCarPlay, in: context)
        #expect(try context.fetchCount(FetchDescriptor<Trip>()) == 2)
    }

    @Test func differentCarIsNeverContinued() throws {
        let (context, car) = try makeContext()
        let other = Vehicle(name: "Bus")
        context.insert(other)
        Trip.save(start: start, end: start + 900, split: split(3, 5), vehicle: car, connection: rsxCarPlay, in: context)
        Trip.save(start: start + 960, end: start + 2_000, split: split(1, 0), vehicle: other, connection: nil, in: context)
        #expect(try context.fetchCount(FetchDescriptor<Trip>()) == 2)
    }

    @Test func unassignedTripsContinueOnlyOnTheSameConnection() throws {
        let (context, _) = try makeContext()
        let lexus = CarConnection(name: "LEXUS ES (Bluetooth)", id: "AA:BB:CC:DD:EE:FF")
        Trip.save(start: start, end: start + 900, split: split(1, 1), vehicle: nil, connection: lexus, in: context)
        Trip.save(start: start + 960, end: start + 1_500, split: split(1, 0), vehicle: nil, connection: lexus, in: context)
        Trip.save(start: start + 1_560, end: start + 2_000, split: split(1, 0), vehicle: nil, connection: rsxCarPlay, in: context)
        #expect(try context.fetchCount(FetchDescriptor<Trip>()) == 2)
    }
}

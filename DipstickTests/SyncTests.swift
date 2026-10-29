//
//  SyncTests.swift
//  DipstickTests
//

import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Dipstick

@MainActor
struct SyncTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Vehicle.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 9, minute: 30))!.addingTimeInterval(0.25)
    }

    /// A car with one of everything.
    @discardableResult
    private func fill(_ context: ModelContext) -> Vehicle {
        let car = Vehicle(name: "Peggy", year: 2004, make: "Acura", model: "RSX", vin: "JH4DC5", currentOdometer: 57_000)
        car.trim = "Type S"
        car.colorHex = "#B8433F"
        car.colorName = "Redondo Red Pearl"
        car.addConnection(CarConnection(name: "Acura (Bluetooth)", id: "1C:50:1E:B4:BC:F1"))
        car.scheduleSource = FactorySchedule.standardSource
        context.insert(car)

        let fuel = FuelEntry(date: date(2026, 10, 1), odometer: 56_800, gallons: 10.0, totalCost: 52.3,
                             isFullTank: false, station: "Chevron", notes: "Premium")
        fuel.addedBy = "Mom"
        context.insert(fuel); fuel.vehicle = car

        let service = MaintenanceEntry(date: date(2026, 9, 1), odometer: 56_500, serviceType: "Brake fluid", cost: 24.5,
                                       notes: "Bleed RR first", nextDueOdometer: nil, nextDueDate: date(2029, 9, 1))
        context.insert(service); service.vehicle = car
        let part = PartUsed(name: "DOT 3", cost: 12.25, partNumber: "08798-9008A", quantity: 2)
        context.insert(part); part.entry = service
        let photo = ReferencePhoto(data: Data([1, 2, 3]), caption: "Bleeder", order: 0)
        context.insert(photo); photo.entry = service

        let trip = Trip(startDate: date(2026, 10, 2), endDate: date(2026, 10, 2).addingTimeInterval(900),
                        cityMiles: 3.5, highwayMiles: 8.25, status: .assigned, connectionName: "Acura", connectionID: "abc")
        trip.addedBy = "Mom"
        context.insert(trip); trip.vehicle = car

        let item = ScheduleItem(name: "Brake fluid", serviceType: "Brake fluid", rule: .init(everyMonths: 36), order: 3)
        item.customEveryMonths = 24
        context.insert(item); item.vehicle = car

        let test = TestEntry(date: date(2026, 8, 1), odometer: 56_000, testType: "Compression", notes: "Warm")
        context.insert(test); test.vehicle = car
        let reading = TestReading(label: "Cylinder 1", value: 180, unit: "psi", order: 0)
        context.insert(reading); reading.entry = test

        let page = ReferencePage(kind: ReferencePage.testKind, name: "Compression")
        page.notes = "Throttle open"
        page.specMin = 135
        context.insert(page); page.vehicle = car
        let pagePhoto = ReferencePhoto(data: Data([9, 9]), order: 1)
        context.insert(pagePhoto); pagePhoto.page = page
        try? context.save()
        return car
    }

    @Test func everyRecordGetsItsOwnID() throws {
        let context = try context()
        fill(context)
        #expect(SyncIDs.assign(in: context) == 11)
        let ids = SyncMapping.records(for: try #require(context.fetch(FetchDescriptor<Vehicle>()).first)).map(\.id)
        #expect(Set(ids).count == ids.count)
        // Already assigned: nothing more to do.
        #expect(SyncIDs.assign(in: context) == 0)
    }

    @Test func aCarRoundTripsThroughSyncRecords() throws {
        let source = try context()
        let car = fill(source)
        let records = SyncMapping.records(for: car)
        #expect(records.count == 11)
        #expect(records.first?.kind == .vehicle)

        let target = try context()
        let skipped = SyncMapping.apply(records.shuffled(), in: target)
        #expect(skipped.isEmpty)
        #expect(BackupSnapshot.make(from: target).data == BackupSnapshot.make(from: source).data)
    }

    @Test func aCarRoundTripsThroughCloudKitRecords() throws {
        let source = try context()
        let car = fill(source)
        let records = SyncMapping.records(for: car)
        let zone = SyncCloudKit.zoneID(forCar: try #require(car.syncID))
        let back = try records.map { try #require(SyncCloudKit.syncRecord(try SyncCloudKit.ckRecord($0, zoneID: zone))) }
        #expect(back == records)
        #expect(SyncCloudKit.carID(for: zone) == car.syncID)
    }

    @Test func applyingAgainUpdatesInsteadOfDuplicating() throws {
        let source = try context()
        let car = fill(source)
        let target = try context()
        SyncMapping.apply(SyncMapping.records(for: car), in: target)

        source.fetchFirst(FuelEntry.self)?.notes = "Regular"
        car.currentOdometer = 56_000 // an older reading from another phone
        SyncMapping.apply(SyncMapping.records(for: car), in: target)

        #expect(try target.fetchCount(FetchDescriptor<FuelEntry>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<Vehicle>()) == 1)
        #expect(target.fetchFirst(FuelEntry.self)?.notes == "Regular")
        // The odometer keeps the higher reading.
        #expect(target.fetchFirst(Vehicle.self)?.currentOdometer == 57_000)
        #expect(target.fetchFirst(FuelEntry.self)?.addedBy == "Mom")
    }

    @Test func aChildWithoutItsParentWaits() throws {
        let source = try context()
        let car = fill(source)
        let fuelOnly = SyncMapping.records(for: car).filter { $0.kind == .fuel }
        let target = try context()
        #expect(SyncMapping.apply(fuelOnly, in: target).count == 1)
        #expect(try target.fetchCount(FetchDescriptor<FuelEntry>()) == 0)
    }

    @Test func deletionsCarryOver() throws {
        let source = try context()
        let car = fill(source)
        let target = try context()
        SyncMapping.apply(SyncMapping.records(for: car), in: target)
        let serviceID = try #require(source.fetchFirst(MaintenanceEntry.self)?.syncID)
        SyncMapping.delete(kind: .service, id: serviceID, in: target)
        #expect(try target.fetchCount(FetchDescriptor<MaintenanceEntry>()) == 0)
        // Its parts and photos go with it.
        #expect(try target.fetchCount(FetchDescriptor<PartUsed>()) == 0)
        #expect(try target.fetchCount(FetchDescriptor<ReferencePhoto>()) == 1)
    }

    @Test func peopleYouShareWithCanOnlyAddRecords() {
        let canAdd = SyncRecord.Kind.allCases.filter(\.participantsCanAdd)
        #expect(Set(canAdd) == [.fuel, .service, .part, .trip, .test, .reading, .photo])
    }

    @Test func backupsKeepIDsAndWhoAddedWhat() throws {
        let source = try context()
        fill(source)
        SyncIDs.assign(in: source)
        let snapshot = BackupSnapshot.make(from: source)
        let target = try context()
        BackupRestore.apply(snapshot.data, photos: snapshot.photos, into: target)
        #expect(target.fetchFirst(Vehicle.self)?.syncID == source.fetchFirst(Vehicle.self)?.syncID)
        #expect(target.fetchFirst(Trip.self)?.addedBy == "Mom")
        #expect(SyncIDs.assign(in: target) == 0)
    }
}

private extension ModelContext {
    func fetchFirst<T: PersistentModel>(_ type: T.Type) -> T? {
        try? fetch(FetchDescriptor<T>()).first
    }
}

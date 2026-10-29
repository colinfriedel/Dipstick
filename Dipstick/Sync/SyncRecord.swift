//
//  SyncRecord.swift
//  Dipstick
//

import Foundation
import SwiftData

/// One record as it travels through iCloud: its kind, its `syncID`, the
/// record it belongs to, and its fields as plain values. Plain on purpose,
/// so turning records into this and back is tested without iCloud
/// (`SyncCloudKit` turns it into a CloudKit record).
nonisolated struct SyncRecord: Equatable {
    enum Kind: String, CaseIterable {
        case vehicle = "Vehicle"
        case fuel = "FuelEntry"
        case service = "MaintenanceEntry"
        case part = "PartUsed"
        case trip = "Trip"
        case scheduleItem = "ScheduleItem"
        case test = "TestEntry"
        case reading = "TestReading"
        case page = "ReferencePage"
        case photo = "ReferencePhoto"

        /// Parents before children, so a child's parent is always there first.
        var level: Int {
            switch self {
            case .vehicle: 0
            case .fuel, .service, .trip, .scheduleItem, .test, .page: 1
            case .part, .reading, .photo: 2
            }
        }

        /// Kinds someone you share a car with may add (they can't change or
        /// delete anything). A part, reading or photo comes with the record
        /// it's part of.
        var participantsCanAdd: Bool {
            switch self {
            case .fuel, .service, .part, .trip, .test, .reading, .photo: true
            case .vehicle, .scheduleItem, .page: false
            }
        }
    }

    enum Value: Equatable {
        case string(String)
        case int(Int)
        case double(Double)
        case bool(Bool)
        case date(Date)
        case data(Data)
    }

    var kind: Kind
    var id: String
    /// The `syncID` of the record this belongs to (nil for a car).
    var parentID: String?
    /// For photos, which can belong to a service or a test's page.
    var parentKind: Kind?
    /// Missing fields are nil.
    var fields: [String: Value] = [:]

    // MARK: Reading fields

    func string(_ key: String) -> String? { if case .string(let v) = fields[key] { v } else { nil } }
    func int(_ key: String) -> Int? { if case .int(let v) = fields[key] { v } else { nil } }
    func double(_ key: String) -> Double? {
        switch fields[key] {
        case .double(let v): v
        case .int(let v): Double(v)
        default: nil
        }
    }
    func bool(_ key: String) -> Bool? { if case .bool(let v) = fields[key] { v } else { nil } }
    func date(_ key: String) -> Date? { if case .date(let v) = fields[key] { v } else { nil } }
    func data(_ key: String) -> Data? { if case .data(let v) = fields[key] { v } else { nil } }

    /// Sets a field, leaving it out when nil.
    mutating func set(_ key: String, _ value: Value?) { fields[key] = value }
}

private extension Optional where Wrapped == String { var value: SyncRecord.Value? { map(SyncRecord.Value.string) } }
private extension Optional where Wrapped == Int { var value: SyncRecord.Value? { map(SyncRecord.Value.int) } }
private extension Optional where Wrapped == Double { var value: SyncRecord.Value? { map(SyncRecord.Value.double) } }
private extension Optional where Wrapped == Date { var value: SyncRecord.Value? { map(SyncRecord.Value.date) } }
private extension Optional where Wrapped == Data { var value: SyncRecord.Value? { map(SyncRecord.Value.data) } }

// MARK: - Records from the database

/// Turns the app's records into `SyncRecord`s and back.
enum SyncMapping {
    /// The ID of a record, giving it one if it has none yet.
    private static func id(_ current: inout String?) -> String {
        if let current { return current }
        let new = SyncIDs.new()
        current = new
        return new
    }

    /// One car and everything that belongs to it, parents first.
    static func records(for vehicle: Vehicle) -> [SyncRecord] {
        var out: [SyncRecord] = []
        let carID = id(&vehicle.syncID)

        var car = SyncRecord(kind: .vehicle, id: carID)
        car.set("name", .string(vehicle.name))
        car.set("year", vehicle.year.value)
        car.set("make", vehicle.make.value)
        car.set("model", vehicle.model.value)
        car.set("trim", vehicle.trim.value)
        car.set("vin", vehicle.vin.value)
        car.set("currentOdometer", .int(vehicle.currentOdometer))
        car.set("colorHex", vehicle.colorHex.value)
        car.set("colorName", vehicle.colorName.value)
        car.set("knownConnections", .string(vehicle.connections.map { "\($0.id)\t\($0.name)" }.joined(separator: "\n")))
        car.set("scheduleSource", vehicle.scheduleSource.value)
        out.append(car)

        for fill in vehicle.fuelEntries ?? [] {
            var r = SyncRecord(kind: .fuel, id: id(&fill.syncID), parentID: carID)
            r.set("date", .date(fill.date))
            r.set("odometer", .int(fill.odometer))
            r.set("gallons", .double(fill.gallons))
            r.set("totalCost", .double(fill.totalCost))
            r.set("isFullTank", .bool(fill.isFullTank))
            r.set("station", fill.station.value)
            r.set("notes", fill.notes.value)
            r.set("addedBy", fill.addedBy.value)
            out.append(r)
        }
        for service in vehicle.maintenanceEntries ?? [] {
            let serviceID = id(&service.syncID)
            var r = SyncRecord(kind: .service, id: serviceID, parentID: carID)
            r.set("date", .date(service.date))
            r.set("odometer", .int(service.odometer))
            r.set("serviceType", .string(service.serviceType))
            r.set("cost", .double(service.cost))
            r.set("notes", service.notes.value)
            r.set("nextDueOdometer", service.nextDueOdometer.value)
            r.set("nextDueDate", service.nextDueDate.value)
            r.set("addedBy", service.addedBy.value)
            out.append(r)
            for part in service.parts ?? [] {
                var p = SyncRecord(kind: .part, id: id(&part.syncID), parentID: serviceID)
                p.set("name", .string(part.name))
                p.set("cost", .double(part.cost))
                p.set("partNumber", part.partNumber.value)
                p.set("quantity", .int(part.quantity))
                out.append(p)
            }
            for photo in service.photos ?? [] {
                out.append(record(for: photo, parentID: serviceID, parentKind: .service))
            }
        }
        for trip in vehicle.trips ?? [] {
            var r = SyncRecord(kind: .trip, id: id(&trip.syncID), parentID: carID)
            r.set("startDate", .date(trip.startDate))
            r.set("endDate", .date(trip.endDate))
            r.set("cityMiles", .double(trip.cityMiles))
            r.set("highwayMiles", .double(trip.highwayMiles))
            r.set("status", .string(trip.statusRaw))
            r.set("connectionName", trip.connectionName.value)
            r.set("connectionID", trip.connectionID.value)
            r.set("addedBy", trip.addedBy.value)
            out.append(r)
        }
        for item in vehicle.scheduleItems ?? [] {
            var r = SyncRecord(kind: .scheduleItem, id: id(&item.syncID), parentID: carID)
            r.set("name", .string(item.name))
            r.set("serviceType", .string(item.serviceType))
            r.set("everyMiles", item.everyMiles.value)
            r.set("everyMonths", item.everyMonths.value)
            r.set("firstMiles", item.firstMiles.value)
            r.set("firstMonths", item.firstMonths.value)
            r.set("customEveryMiles", item.customEveryMiles.value)
            r.set("customEveryMonths", item.customEveryMonths.value)
            r.set("note", item.note.value)
            r.set("order", .int(item.order))
            out.append(r)
        }
        for test in vehicle.testEntries ?? [] {
            let testID = id(&test.syncID)
            var r = SyncRecord(kind: .test, id: testID, parentID: carID)
            r.set("date", .date(test.date))
            r.set("odometer", .int(test.odometer))
            r.set("testType", .string(test.testType))
            r.set("notes", test.notes.value)
            r.set("addedBy", test.addedBy.value)
            out.append(r)
            for reading in test.readings ?? [] {
                var x = SyncRecord(kind: .reading, id: id(&reading.syncID), parentID: testID)
                x.set("label", .string(reading.label))
                x.set("value", reading.value.value)
                x.set("secondValue", reading.secondValue.value)
                x.set("unit", .string(reading.unit))
                x.set("text", reading.text.value)
                x.set("order", .int(reading.order))
                out.append(x)
            }
        }
        for page in vehicle.referencePages ?? [] {
            let pageID = id(&page.syncID)
            var r = SyncRecord(kind: .page, id: pageID, parentID: carID)
            r.set("kind", .string(page.kind))
            r.set("name", .string(page.name))
            r.set("notes", .string(page.notes))
            r.set("specMin", page.specMin.value)
            r.set("specMax", page.specMax.value)
            r.set("specMaxSpread", page.specMaxSpread.value)
            r.set("remindEveryMonths", page.remindEveryMonths.value)
            r.set("remindEveryMiles", page.remindEveryMiles.value)
            out.append(r)
            for photo in page.photos ?? [] {
                out.append(record(for: photo, parentID: pageID, parentKind: .page))
            }
        }
        return out
    }

    private static func record(for photo: ReferencePhoto, parentID: String, parentKind: SyncRecord.Kind) -> SyncRecord {
        var r = SyncRecord(kind: .photo, id: id(&photo.syncID), parentID: parentID, parentKind: parentKind)
        r.set("data", photo.data.value)
        r.set("caption", photo.caption.value)
        r.set("addedAt", .date(photo.addedAt))
        r.set("order", .int(photo.order))
        return r
    }

    // MARK: - Records into the database

    /// The database's records by `syncID`, for matching incoming records.
    struct Index {
        var vehicles: [String: Vehicle] = [:]
        var fuel: [String: FuelEntry] = [:]
        var services: [String: MaintenanceEntry] = [:]
        var parts: [String: PartUsed] = [:]
        var trips: [String: Trip] = [:]
        var scheduleItems: [String: ScheduleItem] = [:]
        var tests: [String: TestEntry] = [:]
        var readings: [String: TestReading] = [:]
        var pages: [String: ReferencePage] = [:]
        var photos: [String: ReferencePhoto] = [:]

        init(_ context: ModelContext) {
            func index<T: PersistentModel>(_ type: T.Type, _ id: KeyPath<T, String?>) -> [String: T] {
                var result: [String: T] = [:]
                for model in (try? context.fetch(FetchDescriptor<T>())) ?? [] {
                    if let key = model[keyPath: id] { result[key] = model }
                }
                return result
            }
            vehicles = index(Vehicle.self, \.syncID)
            fuel = index(FuelEntry.self, \.syncID)
            services = index(MaintenanceEntry.self, \.syncID)
            parts = index(PartUsed.self, \.syncID)
            trips = index(Trip.self, \.syncID)
            scheduleItems = index(ScheduleItem.self, \.syncID)
            tests = index(TestEntry.self, \.syncID)
            readings = index(TestReading.self, \.syncID)
            pages = index(ReferencePage.self, \.syncID)
            photos = index(ReferencePhoto.self, \.syncID)
        }
    }

    /// Adds or updates records from iCloud, matching by `syncID`. Parents
    /// are applied first; a record whose parent isn't here is skipped (it
    /// comes again on the next sync). Returns the records skipped.
    @discardableResult
    static func apply(_ records: [SyncRecord], in context: ModelContext) -> [SyncRecord] {
        var index = Index(context)
        var skipped: [SyncRecord] = []
        for record in records.sorted(by: { $0.kind.level < $1.kind.level }) {
            if !apply(record, index: &index, context: context) { skipped.append(record) }
        }
        context.saveNow()
        return skipped
    }

    /// Removes a record deleted on another phone (and what belongs to it).
    static func delete(kind: SyncRecord.Kind, id: String, in context: ModelContext) {
        let index = Index(context)
        let model: (any PersistentModel)? = switch kind {
        case .vehicle: index.vehicles[id]
        case .fuel: index.fuel[id]
        case .service: index.services[id]
        case .part: index.parts[id]
        case .trip: index.trips[id]
        case .scheduleItem: index.scheduleItems[id]
        case .test: index.tests[id]
        case .reading: index.readings[id]
        case .page: index.pages[id]
        case .photo: index.photos[id]
        }
        if let vehicle = model as? Vehicle { TripRecorder.shared.forget(vehicle) }
        if let model { context.delete(model) }
        context.saveNow()
    }

    private static func apply(_ r: SyncRecord, index: inout Index, context: ModelContext) -> Bool {
        switch r.kind {
        case .vehicle:
            let v = index.vehicles[r.id] ?? {
                let new = Vehicle(name: "")
                new.syncID = r.id
                context.insert(new)
                index.vehicles[r.id] = new
                return new
            }()
            v.name = r.string("name") ?? v.name
            v.year = r.int("year")
            v.make = r.string("make")
            v.model = r.string("model")
            v.trim = r.string("trim")
            v.vin = r.string("vin")
            // The odometer only goes forward: the higher reading wins.
            v.currentOdometer = max(v.currentOdometer, r.int("currentOdometer") ?? 0)
            v.colorHex = r.string("colorHex")
            v.colorName = r.string("colorName")
            v.knownConnections = r.string("knownConnections") ?? ""
            v.connectionID = nil
            v.connectionName = nil
            v.scheduleSource = r.string("scheduleSource")
            return true

        case .fuel:
            guard let car = r.parentID.flatMap({ index.vehicles[$0] }) else { return false }
            let e = index.fuel[r.id] ?? insert(FuelEntry(odometer: 0, gallons: 0, totalCost: 0), id: r.id, into: &index.fuel, context)
            e.date = r.date("date") ?? e.date
            e.odometer = r.int("odometer") ?? 0
            e.gallons = r.double("gallons") ?? 0
            e.totalCost = r.double("totalCost") ?? 0
            e.isFullTank = r.bool("isFullTank") ?? true
            e.station = r.string("station")
            e.notes = r.string("notes")
            e.addedBy = r.string("addedBy")
            e.vehicle = car
            return true

        case .service:
            guard let car = r.parentID.flatMap({ index.vehicles[$0] }) else { return false }
            let e = index.services[r.id] ?? insert(MaintenanceEntry(odometer: 0, serviceType: ""), id: r.id, into: &index.services, context)
            e.date = r.date("date") ?? e.date
            e.odometer = r.int("odometer") ?? 0
            e.serviceType = r.string("serviceType") ?? ""
            e.cost = r.double("cost") ?? 0
            e.notes = r.string("notes")
            e.nextDueOdometer = r.int("nextDueOdometer")
            e.nextDueDate = r.date("nextDueDate")
            e.addedBy = r.string("addedBy")
            e.vehicle = car
            return true

        case .part:
            guard let service = r.parentID.flatMap({ index.services[$0] }) else { return false }
            let p = index.parts[r.id] ?? insert(PartUsed(name: ""), id: r.id, into: &index.parts, context)
            p.name = r.string("name") ?? ""
            p.cost = r.double("cost") ?? 0
            p.partNumber = r.string("partNumber")
            p.quantity = max(r.int("quantity") ?? 1, 1)
            p.entry = service
            return true

        case .trip:
            guard let car = r.parentID.flatMap({ index.vehicles[$0] }) else { return false }
            let t = index.trips[r.id] ?? insert(Trip(startDate: .now, endDate: .now, cityMiles: 0, highwayMiles: 0),
                                                 id: r.id, into: &index.trips, context)
            t.startDate = r.date("startDate") ?? t.startDate
            t.endDate = r.date("endDate") ?? t.endDate
            t.cityMiles = r.double("cityMiles") ?? 0
            t.highwayMiles = r.double("highwayMiles") ?? 0
            t.statusRaw = r.string("status") ?? Trip.Status.assigned.rawValue
            t.connectionName = r.string("connectionName")
            t.connectionID = r.string("connectionID")
            t.addedBy = r.string("addedBy")
            t.vehicle = car
            return true

        case .scheduleItem:
            guard let car = r.parentID.flatMap({ index.vehicles[$0] }) else { return false }
            let i = index.scheduleItems[r.id] ?? insert(ScheduleItem(name: "", serviceType: ""), id: r.id, into: &index.scheduleItems, context)
            i.name = r.string("name") ?? ""
            i.serviceType = r.string("serviceType") ?? ""
            i.everyMiles = r.int("everyMiles")
            i.everyMonths = r.int("everyMonths")
            i.firstMiles = r.int("firstMiles")
            i.firstMonths = r.int("firstMonths")
            i.customEveryMiles = r.int("customEveryMiles")
            i.customEveryMonths = r.int("customEveryMonths")
            i.note = r.string("note")
            i.order = r.int("order") ?? 0
            i.vehicle = car
            return true

        case .test:
            guard let car = r.parentID.flatMap({ index.vehicles[$0] }) else { return false }
            let t = index.tests[r.id] ?? insert(TestEntry(odometer: 0, testType: ""), id: r.id, into: &index.tests, context)
            t.date = r.date("date") ?? t.date
            t.odometer = r.int("odometer") ?? 0
            t.testType = r.string("testType") ?? ""
            t.notes = r.string("notes")
            t.addedBy = r.string("addedBy")
            t.vehicle = car
            return true

        case .reading:
            guard let test = r.parentID.flatMap({ index.tests[$0] }) else { return false }
            let x = index.readings[r.id] ?? insert(TestReading(label: ""), id: r.id, into: &index.readings, context)
            x.label = r.string("label") ?? ""
            x.value = r.double("value")
            x.secondValue = r.double("secondValue")
            x.unit = r.string("unit") ?? ""
            x.text = r.string("text")
            x.order = r.int("order") ?? 0
            x.entry = test
            return true

        case .page:
            guard let car = r.parentID.flatMap({ index.vehicles[$0] }) else { return false }
            let p = index.pages[r.id] ?? insert(ReferencePage(kind: "", name: ""), id: r.id, into: &index.pages, context)
            p.kind = r.string("kind") ?? ReferencePage.serviceKind
            p.name = r.string("name") ?? ""
            p.notes = r.string("notes") ?? ""
            p.specMin = r.double("specMin")
            p.specMax = r.double("specMax")
            p.specMaxSpread = r.double("specMaxSpread")
            p.remindEveryMonths = r.int("remindEveryMonths")
            p.remindEveryMiles = r.int("remindEveryMiles")
            p.vehicle = car
            return true

        case .photo:
            let service = r.parentKind == .service ? r.parentID.flatMap { index.services[$0] } : nil
            let page = r.parentKind == .page ? r.parentID.flatMap { index.pages[$0] } : nil
            guard service != nil || page != nil else { return false }
            let p = index.photos[r.id] ?? insert(ReferencePhoto(data: Data()), id: r.id, into: &index.photos, context)
            if let data = r.data("data") { p.data = data }
            p.caption = r.string("caption")
            p.addedAt = r.date("addedAt") ?? p.addedAt
            p.order = r.int("order") ?? 0
            p.entry = service
            p.page = page
            return true
        }
    }

    private static func insert<T: PersistentModel>(_ model: T, id: String, into index: inout [String: T],
                                                   _ context: ModelContext) -> T {
        context.insert(model)
        model.setSyncID(id)
        index[id] = model
        return model
    }
}

private extension PersistentModel {
    func setSyncID(_ id: String) {
        switch self {
        case let m as Vehicle: m.syncID = id
        case let m as FuelEntry: m.syncID = id
        case let m as MaintenanceEntry: m.syncID = id
        case let m as PartUsed: m.syncID = id
        case let m as Trip: m.syncID = id
        case let m as ScheduleItem: m.syncID = id
        case let m as TestEntry: m.syncID = id
        case let m as TestReading: m.syncID = id
        case let m as ReferencePage: m.syncID = id
        case let m as ReferencePhoto: m.syncID = id
        default: break
        }
    }
}

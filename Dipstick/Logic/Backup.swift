//
//  Backup.swift
//  Dipstick
//

import Foundation
import SwiftData
import CryptoKit

/// Everything the app stores, as plain data: what a backup file holds.
/// Photos are kept as separate files named by their content (`PhotoRecord.file`),
/// so a photo is written once and shared by every backup that has it.
nonisolated struct BackupData: Codable, Equatable {
    static let currentVersion = 1

    var version = BackupData.currentVersion
    var vehicles: [Car] = []
    /// Trips not yet matched to a car.
    var unassignedTrips: [TripRecord] = []

    struct Car: Codable, Equatable {
        var name: String
        var year: Int?
        var make: String?
        var model: String?
        var trim: String?
        var vin: String?
        var currentOdometer: Int
        var colorHex: String?
        var colorName: String?
        var knownConnections: String
        var connectionID: String?
        var connectionName: String?
        var scheduleSource: String?
        var fuel: [FuelRecord] = []
        var services: [ServiceRecord] = []
        var trips: [TripRecord] = []
        var schedule: [ScheduleRecord] = []
        var tests: [TestRecord] = []
        var pages: [PageRecord] = []
    }

    struct FuelRecord: Codable, Equatable {
        var date: Date
        var odometer: Int
        var gallons: Double
        var totalCost: Double
        var isFullTank: Bool
        var station: String?
        var notes: String?
    }

    struct ServiceRecord: Codable, Equatable {
        var date: Date
        var odometer: Int
        var serviceType: String
        var cost: Double
        var notes: String?
        var nextDueOdometer: Int?
        var nextDueDate: Date?
        var parts: [PartRecord] = []
        var photos: [PhotoRecord] = []
    }

    struct PartRecord: Codable, Equatable {
        var name: String
        var cost: Double
        var partNumber: String?
        var quantity: Int
    }

    struct PhotoRecord: Codable, Equatable {
        /// File name in the backup's Photos folder.
        var file: String
        var caption: String?
        var addedAt: Date
        var order: Int
    }

    struct TripRecord: Codable, Equatable {
        var startDate: Date
        var endDate: Date
        var cityMiles: Double
        var highwayMiles: Double
        var status: String
        var connectionName: String?
        var connectionID: String?
    }

    struct ScheduleRecord: Codable, Equatable {
        var name: String
        var serviceType: String
        var everyMiles: Int?
        var everyMonths: Int?
        var firstMiles: Int?
        var firstMonths: Int?
        var customEveryMiles: Int?
        var customEveryMonths: Int?
        var note: String?
        var order: Int
    }

    struct TestRecord: Codable, Equatable {
        var date: Date
        var odometer: Int
        var testType: String
        var notes: String?
        var readings: [ReadingRecord] = []
    }

    struct ReadingRecord: Codable, Equatable {
        var label: String
        var value: Double?
        var secondValue: Double?
        var unit: String
        var text: String?
        var order: Int
    }

    struct PageRecord: Codable, Equatable {
        var kind: String
        var name: String
        var notes: String
        var specMin: Double?
        var specMax: Double?
        var specMaxSpread: Double?
        var remindEveryMonths: Int?
        var remindEveryMiles: Int?
        var photos: [PhotoRecord] = []
    }

    var isEmpty: Bool { vehicles.isEmpty && unassignedTrips.isEmpty }

    /// Every photo file this backup uses.
    var photoFiles: Set<String> {
        Set(vehicles.flatMap { car in
            car.services.flatMap(\.photos).map(\.file) + car.pages.flatMap(\.photos).map(\.file)
        })
    }

    /// "2 cars · 34 fill-ups · 12 services · 3 tests · 8 photos"
    var summary: String {
        func count(_ n: Int, _ word: String) -> String? { n > 0 ? "\(n) \(word)\(n == 1 ? "" : "s")" : nil }
        return [
            count(vehicles.count, "car"),
            count(vehicles.reduce(0) { $0 + $1.fuel.count }, "fill-up"),
            count(vehicles.reduce(0) { $0 + $1.services.count }, "service"),
            count(vehicles.reduce(0) { $0 + $1.tests.count }, "test"),
            count(vehicles.reduce(0) { $0 + $1.trips.count } + unassignedTrips.count, "trip"),
            count(photoFiles.count, "photo"),
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A backup file: when it was made, and the data.
nonisolated struct BackupFile: Codable {
    var app = "Dipstick"
    var created: Date
    var data: BackupData

    /// Dates are stored as seconds since 2001 (how the app keeps them), so
    /// they come back exactly.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    enum ReadError: LocalizedError {
        case notABackup, newerVersion
        var errorDescription: String? {
            switch self {
            case .notABackup: "This isn't a Dipstick backup."
            case .newerVersion: "This backup was made by a newer version of Dipstick. Update the app to restore it."
            }
        }
    }

    static func decode(_ json: Data) throws -> BackupFile {
        guard let file = try? decoder().decode(BackupFile.self, from: json), file.app == "Dipstick" else {
            throw ReadError.notABackup
        }
        guard file.data.version <= BackupData.currentVersion else { throw ReadError.newerVersion }
        return file
    }
}

// MARK: - Making a backup

/// The app's data in plain form, plus the photos it refers to.
nonisolated struct BackupSnapshot {
    var data: BackupData
    /// Photo bytes by file name.
    var photos: [String: Data]

    /// A short fingerprint of the data, to skip backups when nothing changed.
    var fingerprint: String {
        let json = (try? BackupFile.encoder().encode(data)) ?? Data()
        return SHA256.hash(data: json).map { String(format: "%02x", $0) }.joined()
    }

    static func photoFileName(for data: Data) -> String {
        SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined() + ".jpg"
    }
}

extension BackupSnapshot {
    /// Reads everything from the database. Lists are sorted so the same data
    /// always gives the same backup.
    static func make(from context: ModelContext) -> BackupSnapshot {
        var photos: [String: Data] = [:]
        func record(_ photo: ReferencePhoto) -> BackupData.PhotoRecord? {
            guard let bytes = photo.data else { return nil }
            let name = photoFileName(for: bytes)
            photos[name] = bytes
            return .init(file: name, caption: photo.caption, addedAt: photo.addedAt, order: photo.order)
        }
        func photoRecords(_ list: [ReferencePhoto]) -> [BackupData.PhotoRecord] {
            list.sorted { ($0.order, $0.addedAt) < ($1.order, $1.addedAt) }.compactMap(record)
        }
        func trip(_ t: Trip) -> BackupData.TripRecord {
            .init(startDate: t.startDate, endDate: t.endDate, cityMiles: t.cityMiles, highwayMiles: t.highwayMiles,
                  status: t.statusRaw, connectionName: t.connectionName, connectionID: t.connectionID)
        }

        let vehicles = ((try? context.fetch(FetchDescriptor<Vehicle>())) ?? [])
            .sorted { ($0.name, $0.currentOdometer) < ($1.name, $1.currentOdometer) }
        let cars = vehicles.map { v in
            BackupData.Car(
                name: v.name, year: v.year, make: v.make, model: v.model, trim: v.trim, vin: v.vin,
                currentOdometer: v.currentOdometer, colorHex: v.colorHex, colorName: v.colorName,
                knownConnections: v.knownConnections, connectionID: v.connectionID, connectionName: v.connectionName,
                scheduleSource: v.scheduleSource,
                fuel: (v.fuelEntries ?? []).sorted { ($0.date, $0.odometer) < ($1.date, $1.odometer) }.map {
                    .init(date: $0.date, odometer: $0.odometer, gallons: $0.gallons, totalCost: $0.totalCost,
                          isFullTank: $0.isFullTank, station: $0.station, notes: $0.notes)
                },
                services: (v.maintenanceEntries ?? [])
                    .sorted { ($0.date, $0.odometer, $0.serviceType) < ($1.date, $1.odometer, $1.serviceType) }
                    .map { e in
                        .init(date: e.date, odometer: e.odometer, serviceType: e.serviceType, cost: e.cost,
                              notes: e.notes, nextDueOdometer: e.nextDueOdometer, nextDueDate: e.nextDueDate,
                              parts: e.sortedParts.map {
                                  .init(name: $0.name, cost: $0.cost, partNumber: $0.partNumber, quantity: $0.quantity)
                              },
                              photos: photoRecords(e.photos ?? []))
                    },
                trips: (v.trips ?? []).sorted { $0.startDate < $1.startDate }.map(trip),
                schedule: v.sortedScheduleItems.map {
                    .init(name: $0.name, serviceType: $0.serviceType, everyMiles: $0.everyMiles,
                          everyMonths: $0.everyMonths, firstMiles: $0.firstMiles, firstMonths: $0.firstMonths,
                          customEveryMiles: $0.customEveryMiles, customEveryMonths: $0.customEveryMonths,
                          note: $0.note, order: $0.order)
                },
                tests: (v.testEntries ?? [])
                    .sorted { ($0.date, $0.odometer, $0.testType) < ($1.date, $1.odometer, $1.testType) }
                    .map { t in
                        .init(date: t.date, odometer: t.odometer, testType: t.testType, notes: t.notes,
                              readings: t.sortedReadings.map {
                                  .init(label: $0.label, value: $0.value, secondValue: $0.secondValue,
                                        unit: $0.unit, text: $0.text, order: $0.order)
                              })
                    },
                pages: (v.referencePages ?? []).sorted { ($0.kind, $0.name) < ($1.kind, $1.name) }.map { p in
                    .init(kind: p.kind, name: p.name, notes: p.notes, specMin: p.specMin, specMax: p.specMax,
                          specMaxSpread: p.specMaxSpread, remindEveryMonths: p.remindEveryMonths,
                          remindEveryMiles: p.remindEveryMiles, photos: photoRecords(p.photos ?? []))
                }
            )
        }
        let loose = ((try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.vehicle == nil }))) ?? [])
            .sorted { $0.startDate < $1.startDate }
            .map(trip)
        return BackupSnapshot(data: BackupData(vehicles: cars, unassignedTrips: loose), photos: photos)
    }

    /// One CSV per car (fill-ups and services), the same as Export CSV.
    static func csvFiles(from context: ModelContext) -> [String: String] {
        var files: [String: String] = [:]
        for vehicle in (try? context.fetch(FetchDescriptor<Vehicle>())) ?? [] {
            let base = vehicle.name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var name = (base.isEmpty ? "Car" : base) + ".csv"
            var n = 2
            while files[name] != nil { name = "\(base) \(n).csv"; n += 1 }
            files[name] = vehicle.exportCSV()
        }
        return files
    }
}

// MARK: - Restoring

enum BackupRestore {
    /// Replaces everything in the database with the backup. Photos come
    /// from `photos` by file name; any missing are skipped.
    /// - Returns: how many photos were missing.
    @discardableResult
    static func apply(_ data: BackupData, photos: [String: Data], into context: ModelContext) -> Int {
        for vehicle in (try? context.fetch(FetchDescriptor<Vehicle>())) ?? [] { context.delete(vehicle) }
        for trip in (try? context.fetch(FetchDescriptor<Trip>())) ?? [] where trip.vehicle == nil { context.delete(trip) }
        // Anything left without an owner (normally nothing).
        for photo in (try? context.fetch(FetchDescriptor<ReferencePhoto>())) ?? [] where photo.entry == nil && photo.page == nil {
            context.delete(photo)
        }

        var missing = 0
        func insertPhotos(_ records: [BackupData.PhotoRecord], attach: (ReferencePhoto) -> Void) {
            for r in records {
                guard let bytes = photos[r.file] else { missing += 1; continue }
                let photo = ReferencePhoto(data: bytes, caption: r.caption, order: r.order)
                photo.addedAt = r.addedAt
                context.insert(photo)
                attach(photo)
            }
        }
        func insertTrip(_ r: BackupData.TripRecord, to vehicle: Vehicle?) {
            let trip = Trip(startDate: r.startDate, endDate: r.endDate, cityMiles: r.cityMiles,
                            highwayMiles: r.highwayMiles, connectionName: r.connectionName,
                            connectionID: r.connectionID)
            trip.statusRaw = r.status
            context.insert(trip)
            trip.vehicle = vehicle
        }

        for car in data.vehicles {
            let v = Vehicle(name: car.name, year: car.year, make: car.make, model: car.model, vin: car.vin,
                            currentOdometer: car.currentOdometer)
            v.trim = car.trim
            v.colorHex = car.colorHex
            v.colorName = car.colorName
            v.knownConnections = car.knownConnections
            v.connectionID = car.connectionID
            v.connectionName = car.connectionName
            v.scheduleSource = car.scheduleSource
            context.insert(v)

            for r in car.fuel {
                let e = FuelEntry(date: r.date, odometer: r.odometer, gallons: r.gallons, totalCost: r.totalCost,
                                  isFullTank: r.isFullTank, station: r.station, notes: r.notes)
                context.insert(e)
                e.vehicle = v
            }
            for r in car.services {
                let e = MaintenanceEntry(date: r.date, odometer: r.odometer, serviceType: r.serviceType, cost: r.cost,
                                         notes: r.notes, nextDueOdometer: r.nextDueOdometer, nextDueDate: r.nextDueDate)
                context.insert(e)
                e.vehicle = v
                for p in r.parts {
                    let part = PartUsed(name: p.name, cost: p.cost, partNumber: p.partNumber, quantity: p.quantity)
                    context.insert(part)
                    part.entry = e
                }
                insertPhotos(r.photos) { $0.entry = e }
            }
            for r in car.trips { insertTrip(r, to: v) }
            for r in car.schedule {
                let item = ScheduleItem(name: r.name, serviceType: r.serviceType, note: r.note, order: r.order)
                item.everyMiles = r.everyMiles
                item.everyMonths = r.everyMonths
                item.firstMiles = r.firstMiles
                item.firstMonths = r.firstMonths
                item.customEveryMiles = r.customEveryMiles
                item.customEveryMonths = r.customEveryMonths
                context.insert(item)
                item.vehicle = v
            }
            for r in car.tests {
                let t = TestEntry(date: r.date, odometer: r.odometer, testType: r.testType, notes: r.notes)
                context.insert(t)
                t.vehicle = v
                for reading in r.readings {
                    let x = TestReading(label: reading.label, value: reading.value, secondValue: reading.secondValue,
                                        unit: reading.unit, text: reading.text, order: reading.order)
                    context.insert(x)
                    x.entry = t
                }
            }
            for r in car.pages {
                let page = ReferencePage(kind: r.kind, name: r.name)
                page.notes = r.notes
                page.specMin = r.specMin
                page.specMax = r.specMax
                page.specMaxSpread = r.specMaxSpread
                page.remindEveryMonths = r.remindEveryMonths
                page.remindEveryMiles = r.remindEveryMiles
                context.insert(page)
                page.vehicle = v
                insertPhotos(r.photos) { $0.page = page }
            }
        }
        for r in data.unassignedTrips { insertTrip(r, to: nil) }
        context.saveNow()
        return missing
    }
}

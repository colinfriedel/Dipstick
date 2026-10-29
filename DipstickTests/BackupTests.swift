//
//  BackupTests.swift
//  DipstickTests
//

import Foundation
import SwiftData
import Testing
@testable import Dipstick

@MainActor
struct BackupTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Vehicle.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 9, minute: 30, second: 12))!
            .addingTimeInterval(0.25)
    }

    /// One of everything the app stores.
    private func fill(_ context: ModelContext) {
        let car = Vehicle(name: "Acura RSX", year: 2004, make: "Acura", model: "RSX", vin: "JH4DC5", currentOdometer: 57_000)
        car.trim = "Type S"
        car.colorHex = "#C0392B"
        car.colorName = "Red"
        car.knownConnections = "abc|Acura"
        context.insert(car)

        let fill = FuelEntry(date: date(2026, 10, 1), odometer: 56_800, gallons: 11.2, totalCost: 52.3,
                             station: "Chevron", notes: "Premium")
        context.insert(fill)
        fill.vehicle = car

        let service = MaintenanceEntry(date: date(2026, 9, 1), odometer: 56_500, serviceType: "Brake fluid",
                                       cost: 24.5, notes: "Bleed RR first", nextDueOdometer: 86_500,
                                       nextDueDate: date(2029, 9, 1))
        context.insert(service)
        service.vehicle = car
        let part = PartUsed(name: "DOT 3", cost: 12.25, partNumber: "08798-9008A", quantity: 2)
        context.insert(part)
        part.entry = service
        let photo = ReferencePhoto(data: Data([1, 2, 3]), caption: "Bleeder", order: 0)
        context.insert(photo)
        photo.entry = service

        let trip = Trip(startDate: date(2026, 10, 2), endDate: date(2026, 10, 2).addingTimeInterval(900),
                        cityMiles: 3.5, highwayMiles: 8.25, status: .assigned, connectionName: "Acura", connectionID: "abc")
        context.insert(trip)
        trip.vehicle = car
        context.insert(Trip(startDate: date(2026, 10, 3), endDate: date(2026, 10, 3), cityMiles: 1, highwayMiles: 0))

        let item = ScheduleItem(name: "Brake fluid", serviceType: "Brake fluid",
                                rule: .init(everyMiles: 30_000, everyMonths: 36), note: "Severe: 2 yr", order: 3)
        item.customEveryMonths = 24
        context.insert(item)
        item.vehicle = car

        let test = TestEntry(date: date(2026, 8, 1), odometer: 56_000, testType: "Compression", notes: "Warm")
        context.insert(test)
        test.vehicle = car
        for i in 0..<2 {
            let reading = TestReading(label: "Cylinder \(i + 1)", value: 180 - Double(i), unit: "psi", order: i)
            context.insert(reading)
            reading.entry = test
        }

        let page = ReferencePage(kind: ReferencePage.testKind, name: "Compression")
        page.notes = "Throttle open"
        page.specMin = 135
        page.specMaxSpread = 28
        context.insert(page)
        page.vehicle = car
        let pagePhoto = ReferencePhoto(data: Data([9, 9]), order: 0)
        context.insert(pagePhoto)
        pagePhoto.page = page
        context.saveNow()
    }

    @Test func backupAndRestoreGiveBackTheSameData() throws {
        let source = try context()
        fill(source)
        let snapshot = BackupSnapshot.make(from: source)
        #expect(snapshot.photos.count == 2)
        #expect(snapshot.data.unassignedTrips.count == 1)

        let json = try BackupFile.encoder().encode(BackupFile(created: .now, data: snapshot.data))
        let file = try BackupFile.decode(json)
        #expect(file.data == snapshot.data)

        let target = try context()
        let other = Vehicle(name: "Old car")
        target.insert(other)
        target.saveNow()
        let missing = BackupRestore.apply(file.data, photos: snapshot.photos, into: target)
        #expect(missing == 0)

        let restored = BackupSnapshot.make(from: target)
        #expect(restored.data == snapshot.data)
        #expect(restored.photos == snapshot.photos)
        #expect(restored.fingerprint == snapshot.fingerprint)
        #expect(try target.fetchCount(FetchDescriptor<Vehicle>()) == 1)
    }

    @Test func missingPhotosAreSkippedAndCounted() throws {
        let source = try context()
        fill(source)
        let snapshot = BackupSnapshot.make(from: source)
        let target = try context()
        let missing = BackupRestore.apply(snapshot.data, photos: [:], into: target)
        #expect(missing == 2)
        #expect(try target.fetchCount(FetchDescriptor<ReferencePhoto>()) == 0)
    }

    @Test func notABackupIsRejected() {
        #expect(throws: BackupFile.ReadError.self) { try BackupFile.decode(Data("{\"hello\":1}".utf8)) }
    }

    @Test func keepsAWeekMonthliesAndThreeRestores() {
        var names: [String] = []
        // Every day from June 1 to Oct 26.
        var day = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let end = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 26))!
        while day <= end {
            names.append(BackupFiles.dayFolderName(for: day))
            day = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        }
        names += ["2026-10-01 10.00 before restore", "2026-10-02 10.00 before restore",
                  "2026-10-03 10.00 before restore", "2026-10-04 10.00 before restore"]

        let keep = BackupFiles.namesToKeep(names)
        #expect(keep == [
            "2026-10-26", "2026-10-25", "2026-10-24", "2026-10-23", "2026-10-22", "2026-10-21", "2026-10-20",
            "2026-09-30", "2026-08-31", "2026-07-31", "2026-06-30",
            "2026-10-02 10.00 before restore", "2026-10-03 10.00 before restore", "2026-10-04 10.00 before restore",
        ])
    }

    @Test func writesListsReadsAndPrunesFiles() throws {
        let root = URL.temporaryDirectory.appending(path: "BackupTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let context = try context()
        fill(context)
        let snapshot = BackupSnapshot.make(from: context)
        let csv = BackupSnapshot.csvFiles(from: context)
        #expect(csv.keys.sorted() == ["Acura RSX.csv"])

        // Ten days of backups; the photo of an old service is only in the oldest.
        let old = BackupSnapshot(data: BackupData(), photos: ["old.jpg": Data([7])])
        var oldData = BackupData()
        oldData.vehicles = [.init(name: "Old", currentOdometer: 0, knownConnections: "",
                                  services: [.init(date: .now, odometer: 0, serviceType: "x", cost: 0,
                                                   photos: [.init(file: "old.jpg", addedAt: .now, order: 0)])])]
        try BackupFiles.write(BackupSnapshot(data: oldData, photos: old.photos), created: .now, csv: [:],
                              folder: "2026-01-05", in: root)
        for d in 10...19 {
            try BackupFiles.write(snapshot, created: .now, csv: csv, folder: "2026-02-\(d)", in: root)
        }
        #expect(BackupFiles.list(in: root).count == 11)

        BackupFiles.prune(in: root)
        let names = BackupFiles.list(in: root).map(\.name)
        // The last 7 days (Feb 13–19), plus January's newest.
        #expect(names == ["2026-02-19", "2026-02-18", "2026-02-17", "2026-02-16", "2026-02-15",
                          "2026-02-14", "2026-02-13", "2026-01-05"])
        let photos = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Photos").path(percentEncoded: false))
        #expect(Set(photos) == Set(snapshot.photos.keys).union(["old.jpg"]))

        let (file, read) = try BackupFiles.read(BackupFiles.list(in: root)[0], in: root)
        #expect(file.data == snapshot.data)
        #expect(read == snapshot.photos)

        // Once January's backup is gone, its photo goes too.
        try FileManager.default.removeItem(at: root.appending(path: "2026-01-05"))
        BackupFiles.prune(in: root)
        let after = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Photos").path(percentEncoded: false))
        #expect(Set(after) == Set(snapshot.photos.keys))
    }
}

@MainActor
struct BackupUploadTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func fineWhenUploadedOrJustWritten() {
        #expect(BackupFiles.uploadProblem(.init(), now: now) == nil)
        #expect(BackupFiles.uploadProblem(.init(oldestWaiting: now.addingTimeInterval(-3600)), now: now) == nil)
    }

    @Test func fullICloudStorageIsNamed() {
        let quota = NSError(domain: NSCocoaErrorDomain, code: NSUbiquitousFileNotUploadedDueToQuotaError)
        let other = NSError(domain: NSCocoaErrorDomain, code: NSUbiquitousFileUbiquityServerNotAvailable)
        #expect(BackupFiles.uploadProblem(.init(errors: [other, quota]), now: now)?.contains("storage is full") == true)
        #expect(BackupFiles.uploadProblem(.init(errors: [other]), now: now)?.hasPrefix("Backups aren't reaching iCloud (") == true)
    }

    @Test func waitingOverADayIsAProblem() {
        let status = BackupFiles.UploadStatus(oldestWaiting: now.addingTimeInterval(-25 * 3600))
        #expect(BackupFiles.uploadProblem(status, now: now)?.contains("over a day") == true)
    }
}

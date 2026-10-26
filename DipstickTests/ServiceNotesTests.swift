//
//  ServiceNotesTests.swift
//  DipstickTests
//

import Foundation
import SwiftData
import Testing
@testable import Dipstick

@MainActor
struct ServiceNotesTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Vehicle.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @discardableResult
    private func log(_ type: String, on day: Date, at odometer: Int, notes: String? = nil,
                     car: Vehicle, in context: ModelContext) -> MaintenanceEntry {
        let entry = MaintenanceEntry(date: day, odometer: odometer, serviceType: type, notes: notes)
        context.insert(entry)
        entry.vehicle = car
        return entry
    }

    private func page(_ name: String, notes: String, photos: Int, car: Vehicle, in context: ModelContext) -> ReferencePage {
        let page = car.referencePageCreating(kind: ReferencePage.serviceKind, name: name, in: context)
        page.notes = notes
        for i in 0..<photos {
            let photo = ReferencePhoto(data: Data([UInt8(i)]), caption: "Photo \(i)", order: i)
            context.insert(photo)
            photo.page = page
        }
        return page
    }

    @Test func oldPageMovesOntoLatestServiceOfItsType() throws {
        let context = try context()
        let car = Vehicle(name: "Acura")
        context.insert(car)
        log("Brake fluid", on: date(2024, 3, 1), at: 50_000, car: car, in: context)
        let latest = log("brake fluid", on: date(2026, 10, 1), at: 57_000, notes: "Used a vacuum bleeder.",
                         car: car, in: context)
        _ = page("Brake Fluid", notes: "Bleed RR, LR, RF, LF", photos: 2, car: car, in: context)

        ServiceNotesMove.run(in: context)

        #expect(latest.notes == "Used a vacuum bleeder.\n\nBleed RR, LR, RF, LF")
        #expect(latest.sortedPhotos.map(\.caption) == ["Photo 0", "Photo 1"])
        #expect(car.referencePage(kind: ReferencePage.serviceKind, name: "Brake fluid") == nil)
        #expect(try context.fetchCount(FetchDescriptor<ReferencePhoto>()) == 2)
        #expect(car.pastServiceNotes(ofType: "Brake fluid").map(\.odometer) == [57_000])

        // Running again changes nothing.
        ServiceNotesMove.run(in: context)
        #expect(latest.notes == "Used a vacuum bleeder.\n\nBleed RR, LR, RF, LF")
    }

    @Test func pageForServiceNeverLoggedStaysAndTestPagesAreLeftAlone() throws {
        let context = try context()
        let car = Vehicle(name: "Acura")
        context.insert(car)
        _ = page("Timing belt", notes: "Buy the kit", photos: 1, car: car, in: context)
        let testPage = car.referencePageCreating(kind: ReferencePage.testKind, name: "Brake fluid", in: context)
        testPage.notes = "Spec 3% max"
        log("Brake fluid", on: date(2026, 10, 1), at: 57_000, car: car, in: context)

        ServiceNotesMove.run(in: context)

        #expect(car.leftoverServicePage(ofType: "Timing belt")?.notes == "Buy the kit")
        #expect(car.hasPastServiceNotes(ofType: "Timing belt"))
        #expect(car.referencePage(kind: ReferencePage.testKind, name: "Brake fluid")?.notes == "Spec 3% max")
        #expect(!car.hasPastServiceNotes(ofType: "Brake fluid"))
    }

    @Test func pastNotesAreNewestFirstAndLeaveOutTheOneBeingEdited() throws {
        let context = try context()
        let car = Vehicle(name: "Acura")
        context.insert(car)
        let old = log("Oil change", on: date(2025, 1, 1), at: 52_000, notes: "5W-30, 4.2 qt", car: car, in: context)
        log("Oil change", on: date(2025, 6, 1), at: 54_000, notes: "  ", car: car, in: context)
        let new = log("Oil change", on: date(2026, 1, 1), at: 56_000, car: car, in: context)
        let photo = ReferencePhoto(data: Data([1]))
        context.insert(photo)
        photo.entry = new

        #expect(car.pastServiceNotes(ofType: "Oil change").map(\.odometer) == [56_000, 52_000])
        #expect(car.pastServiceNotes(ofType: "Oil change", excluding: new).map(\.odometer) == [52_000])
        #expect(car.pastServiceNotes(ofType: "Oil change", excluding: old).map(\.odometer) == [56_000])
    }
}

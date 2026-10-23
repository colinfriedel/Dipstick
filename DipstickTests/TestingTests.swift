//
//  TestingTests.swift
//  DipstickTests
//

import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
@testable import Dipstick

@MainActor
struct TestingTests {
    private func context() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Vehicle.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @discardableResult
    private func log(_ type: String, _ values: [Double], unit: String = "psi", on day: Date, at odometer: Int,
                     car: Vehicle, in context: ModelContext) -> TestEntry {
        let entry = TestEntry(date: day, odometer: odometer, testType: type)
        context.insert(entry)
        entry.vehicle = car
        for (i, value) in values.enumerated() {
            let reading = TestReading(label: "Cylinder \(i + 1)", value: value, unit: unit, order: i)
            context.insert(reading)
            reading.entry = entry
        }
        return entry
    }

    @Test func specFlagsLowHighAndSpread() {
        let spec = TestSpec.Spec(min: 135, max: nil, maxSpread: 28)
        #expect(TestSpec.problems([180, 175, 178, 182], spec: spec).isEmpty)
        // 130 is low (and 52 below the best cylinder, which is flagged too).
        #expect(TestSpec.problems([180, 130, 178, 182], spec: spec) == [1: "below 135", 3: "spread 52 (max 28)"])
        // 140 is in range but 42 below the best cylinder.
        let spread = TestSpec.problems([182, 140, 178, 180], spec: spec)
        #expect(spread[1] == "spread 42 (max 28)" && spread[0] == "spread 42 (max 28)" && spread.count == 2)
        #expect(TestSpec.problems([nil, 120], spec: spec) == [1: "below 135"])
        #expect(TestSpec.problems([14.9], spec: .init(max: 14.7)) == [0: "above 14.7"])
    }

    @Test func templatesAndOptions() {
        let compression = TestTemplate.template(named: "compression TEST")
        #expect(compression?.labels(cylinders: 4) == ["Cylinder 1", "Cylinder 2", "Cylinder 3", "Cylinder 4"])
        #expect(compression?.secondLabel == "Wet")
        #expect(TestTemplate.template(named: "Tire tread")?.labels(cylinders: 4) == TestTemplate.corners)
        let options = TestTemplate.options(addingUsed: ["Vacuum gauge", "compression test", "Vacuum gauge"])
        #expect(options.prefix(TestTemplate.builtIn.count).elementsEqual(TestTemplate.builtIn.map(\.name)))
        #expect(options.last == "Vacuum gauge" && options.count == TestTemplate.builtIn.count + 1)
    }

    @Test func historySummaryAndChart() throws {
        let context = try context()
        let car = Vehicle(name: "Acura", currentOdometer: 57_000)
        context.insert(car)
        log("Compression test", [180, 175, 178, 182], on: date(2025, 10, 1), at: 52_000, car: car, in: context)
        let latest = log("Compression test", [178, 172, 177, 180], on: date(2026, 10, 22), at: 56_900, car: car, in: context)
        log("Leak-down test", [5, 6, 5, 7], unit: "%", on: date(2026, 10, 22), at: 56_900, car: car, in: context)

        let history = car.tests(ofType: "compression test")
        #expect(history.map(\.odometer) == [56_900, 52_000])
        #expect(latest.summary == "178 · 172 · 177 · 180 psi")

        let chart = try #require(TestChartData(history: history, template: TestTemplate.template(named: "Compression test")))
        #expect(chart.labels == ["Cylinder 1", "Cylinder 2", "Cylinder 3", "Cylinder 4"])
        #expect(chart.points.count == 8 && chart.dates == 2 && chart.unit == "psi")
    }

    @Test func referencePagesAndSpecProblems() throws {
        let context = try context()
        let car = Vehicle(name: "Acura")
        context.insert(car)
        #expect(car.referencePage(kind: ReferencePage.testKind, name: "Compression test") == nil)
        let page = car.referencePageCreating(kind: ReferencePage.testKind, name: "Compression test", in: context)
        page.specMin = 135
        page.specMaxSpread = 28
        // Same page again (any case), and service pages are separate.
        #expect(car.referencePageCreating(kind: ReferencePage.testKind, name: "COMPRESSION TEST", in: context) === page)
        #expect(car.referencePage(kind: ReferencePage.serviceKind, name: "Compression test") == nil)

        let entry = log("Compression test", [180, 130, 178, 182], on: Date(), at: 56_900, car: car, in: context)
        let problems = entry.specProblems(page: page)
        #expect(problems.count == 2)  // 130 is low, and 52 below the best
        #expect(problems[entry.sortedReadings[1].persistentModelID] == "below 135")
    }

    @Test func reminderFromThePage() throws {
        let context = try context()
        let car = Vehicle(name: "Acura", currentOdometer: 57_000)
        context.insert(car)
        #expect(car.testReminder(for: "Battery and charging") == nil)
        let page = car.referencePageCreating(kind: ReferencePage.testKind, name: "Battery and charging", in: context)
        page.remindEveryMonths = 12
        #expect(car.testReminder(for: "Battery and charging")?.lastDone == nil)  // never done: due
        log("Battery and charging", [12.6], unit: "V", on: date(2025, 1, 1), at: 50_000, car: car, in: context)
        let reminder = car.testReminder(for: "Battery and charging", today: date(2026, 10, 22))
        #expect(reminder?.status == .overdue)
    }

    @Test func deletingTheCarDeletesTestsAndPages() throws {
        let context = try context()
        let car = Vehicle(name: "Acura")
        context.insert(car)
        log("Compression test", [180], on: Date(), at: 1, car: car, in: context)
        let page = car.referencePageCreating(kind: ReferencePage.serviceKind, name: "Brake fluid", in: context)
        let photo = ReferencePhoto(data: Data([1, 2, 3]))
        context.insert(photo)
        photo.page = page
        try context.save()
        context.delete(car)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<TestEntry>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<TestReading>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ReferencePage>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ReferencePhoto>()) == 0)
    }

    @Test func photosAreDownsized() throws {
        let width = 4_000, height = 3_000
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)

        let small = try #require(PhotoStore.downsized(data as Data))
        let image = try #require(PhotoStore.thumbnail(small, maxPixels: 10_000))
        #expect(max(image.width, image.height) == 2_000)
    }
}

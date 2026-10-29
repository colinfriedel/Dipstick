//
//  ScheduleReaderTests.swift
//  DipstickTests
//

import Foundation
import SwiftData
import Testing
@testable import Dipstick

struct ScheduleReaderTests {
    @Test func readsHeaderNumbers() {
        // In tenths, so 7.5 (thousand) survives until the scale is known.
        #expect(ScheduleReader.headerNumber("10") == 100)
        #expect(ScheduleReader.headerNumber("7.5") == 75)
        #expect(ScheduleReader.headerNumber("7,500") == 75_000)
        #expect(ScheduleReader.headerNumber("15K") == 150_000)
        #expect(ScheduleReader.headerNumber("Months") == nil)
        #expect(ScheduleReader.headerNumber("1.2.3") == nil)
    }

    @Test func intervalFromMarkedColumns() {
        #expect(ScheduleReader.interval([7_500, 15_000, 22_500, 30_000]) == (7_500, nil, false))
        #expect(ScheduleReader.interval([30_000, 60_000, 90_000]) == (30_000, nil, false))
        // First at 120,000, then every 60,000.
        #expect(ScheduleReader.interval([120_000, 180_000]) == (60_000, 120_000, false))
        // One mark: when it's first due, to check.
        #expect(ScheduleReader.interval([60_000]) == (nil, 60_000, true))
        // A missed mark leaves a double gap: still the usual spacing, checked.
        #expect(ScheduleReader.interval([10, 20, 40, 50]) == (10, nil, true))
        #expect(ScheduleReader.interval([]) == (nil, nil, false))
    }

    @Test func readsIntervalsAsWritten() {
        #expect(ScheduleReader.listInterval("Replace engine oil every 7,500 miles or 12 months")
                == .init(everyMiles: 7_500, everyMonths: 12))
        #expect(ScheduleReader.listInterval("Brake fluid: every 3 years") == .init(everyMonths: 36))
        #expect(ScheduleReader.listInterval("Tire rotation every 5k miles") == .init(everyMiles: 5_000))
        #expect(ScheduleReader.listInterval("Coolant: at 150,000 miles or 10 years, then every 100,000 miles or 5 years")
                == .init(everyMiles: 100_000, everyMonths: 60, firstMiles: 150_000, firstMonths: 120))
        #expect(ScheduleReader.listInterval("Check tire pressure monthly") == nil)
        // Small numbers aren't mileage ("2 miles").
        #expect(ScheduleReader.listInterval("Drive 2 miles to warm up") == nil)
    }

    @Test func readsAList() {
        let text = """
            Scheduled maintenance
            Engine oil and filter: replace every 10,000 miles or 12 months
            Tire rotation: every 5,000 miles
            Spark plugs: replace every 100,000 miles
            Check tire pressure monthly.
            """
        let items = ScheduleReader.readList(text)
        #expect(items.map(\.name) == ["Replace engine oil and filter", "Tire rotation", "Replace spark plugs"])
        #expect(items.map(\.serviceType) == ["Oil change", "Tire rotation", "Spark plugs"])
        #expect(items[0].everyMiles == 10_000 && items[0].everyMonths == 12)
    }

    @Test func cleansNames() {
        #expect(ScheduleReader.cleanName("• REPLACE ENGINE OIL:") == "Replace engine oil")
        #expect(ScheduleReader.cleanName("Spark plugs: replace") == "Replace spark plugs")
        #expect(ScheduleReader.cleanName("Rotate   tires") == "Rotate tires")
    }

    /// A drawn page: a header of mileage columns, a months row, and rows
    /// with ink where marked.
    private func gridPage(rows: [(String, [Int])]) -> ([ScheduleReader.Box], ScheduleReader.InkMap) {
        let columnX = [0.45, 0.52, 0.59, 0.66, 0.73, 0.80, 0.87, 0.94]
        let miles = ["7.5", "15", "22.5", "30", "37.5", "45", "52.5", "60"]
        let months = ["6", "12", "18", "24", "30", "36", "42", "48"]
        var boxes = [ScheduleReader.Box(text: "Miles (x1000)", minX: 0.03, maxX: 0.18, minY: 0.10, maxY: 0.13)]
        boxes += zip(columnX, miles).map { .init(text: $1, minX: $0 - 0.015, maxX: $0 + 0.015, minY: 0.10, maxY: 0.13) }
        boxes.append(.init(text: "Months", minX: 0.03, maxX: 0.10, minY: 0.15, maxY: 0.18))
        boxes += zip(columnX, months).map { .init(text: $1, minX: $0 - 0.01, maxX: $0 + 0.01, minY: 0.15, maxY: 0.18) }

        let size = 400
        var pixels = [UInt8](repeating: 255, count: size * size)
        for (n, row) in rows.enumerated() {
            let top = 0.25 + Double(n) * 0.06
            boxes.append(.init(text: row.0, minX: 0.03, maxX: 0.35, minY: top, maxY: top + 0.035))
            for column in row.1 {
                let cx = Int(columnX[column] * Double(size)), cy = Int((top + 0.0175) * Double(size))
                for y in (cy - 3)...(cy + 3) { for x in (cx - 3)...(cx + 3) { pixels[y * size + x] = 0 } }
            }
        }
        return (boxes, ScheduleReader.InkMap(width: size, height: size, pixels: pixels))
    }

    @Test func readsAGridFromInk() throws {
        let (boxes, ink) = gridPage(rows: [
            ("Replace engine oil and filter", Array(0..<8)),
            ("Replace cabin air filter", [1, 3, 5, 7]),
            ("Replace engine air filter", [3, 7]),
            ("Replace spark plugs", [7]),
        ])
        let items = try #require(ScheduleReader.readGrid(boxes, ink: ink))
        #expect(items.map(\.name) == ["Replace engine oil and filter", "Replace cabin air filter",
                                      "Replace engine air filter", "Replace spark plugs"])
        #expect(items.map(\.serviceType) == ["Oil change", "Cabin air filter", "Air filter", "Spark plugs"])
        #expect(items.map(\.everyMiles) == [7_500, 15_000, 30_000, nil])
        #expect(items.map(\.everyMonths) == [6, 12, 24, nil])
        #expect(items[3].firstMiles == 60_000 && items[3].firstMonths == 48)
        #expect(items.map(\.unsure) == [false, false, false, true])
    }

    @Test func notesUnderAGridWin() throws {
        let (boxes, ink) = gridPage(rows: [("Replace engine oil", Array(0..<8)), ("Replace brake fluid", [5])])
        let grid = try #require(ScheduleReader.readGrid(boxes, ink: ink))
        let items = ScheduleReader.withNotes(grid, from: "Replace brake fluid every 3 years regardless of mileage.", known: [])
        #expect(items[1].everyMonths == 36 && items[1].everyMiles == nil && items[1].firstMiles == nil)
        #expect(!items[1].unsure)
    }

    @Test func aPageWithoutColumnsIsntAGrid() {
        let boxes = [ScheduleReader.Box(text: "Replace engine oil every 7,500 miles", minX: 0.05, maxX: 0.9, minY: 0.1, maxY: 0.13)]
        #expect(ScheduleReader.readGrid(boxes) == nil)
    }

    @Test func flagsNumbersNotOnThePage() {
        var item = ScheduleReader.Item(name: "Oil", serviceType: "Oil change", everyMiles: 7_500, everyMonths: 36)
        ScheduleReader.check(&item, against: .init("every 7,500 miles or 3 years"))
        #expect(!item.unsure)
        ScheduleReader.check(&item, against: .init("every 5,000 miles"))
        #expect(item.unsure)
    }

    @MainActor
    @Test func newCarsStartOnTheStandardScheduleAndAManualReplacesIt() throws {
        let context = ModelContext(try ModelContainer(for: Vehicle.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let car = Vehicle(name: "Civic")
        context.insert(car)
        car.loadSchedule(FactorySchedule.standard(forYear: nil), into: context)
        car.scheduleSource = FactorySchedule.standardSource
        #expect(car.hasStandardSchedule)
        #expect(car.sortedScheduleItems.contains { $0.serviceType == "Oil change" })

        car.replaceSchedule(with: [.init(name: "Replace engine oil", serviceType: "Oil change",
                                         rule: .init(everyMiles: 7_500, everyMonths: 12))],
                            source: FactorySchedule.manualSource, in: context)
        context.saveNow()
        #expect(!car.hasStandardSchedule)
        #expect(car.sortedScheduleItems.map(\.name) == ["Replace engine oil"])
        #expect(try context.fetchCount(FetchDescriptor<ScheduleItem>()) == 1)
    }
}

struct ManualPDFTests {
    @Test func findsTheSchedulePagesInAWholeManual() {
        var pages = Array(repeating: "Adjusting the mirrors. Fold the mirrors before washing the car.", count: 300)
        pages[211] = "Maintenance schedule. Replace engine oil every 7,500 miles or 12 months. Rotate tires every 7,500 miles. Replace air cleaner every 30,000 miles. Inspect brakes."
        pages[212] = "Replace spark plugs every 105,000 miles."
        pages[40] = "Tire pressure: check monthly."
        #expect(ScheduleReader.schedulePageIndexes(pages) == [211, 212])
    }

    @Test func readsShortPDFsWholeAndScansUpToALimit() {
        #expect(ScheduleReader.schedulePageIndexes(["a", "b"]) == [0, 1])
        #expect(ScheduleReader.schedulePageIndexes(Array(repeating: "", count: 200)).count == ScheduleReader.maxScannedPages)
        #expect(ScheduleReader.schedulePageIndexes(Array(repeating: "Nothing about upkeep in this long page of text.", count: 50)).isEmpty)
    }

}

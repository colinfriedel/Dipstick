//
//  RecordCSVTests.swift
//  DipstickTests
//

import Foundation
import Testing
@testable import Dipstick

@MainActor
struct CSVTests {
    @Test func parsesQuotesCommasAndNewlines() {
        let rows = CSV.parse("a,\"b,c\",\"say \"\"hi\"\"\"\r\n1,\"two\nlines\",\n\n")
        #expect(rows == [["a", "b,c", "say \"hi\""], ["1", "two\nlines", ""]])
    }

    @Test func stripsByteOrderMark() {
        #expect(CSV.parse("\u{FEFF}type,date\nfuel,2026-01-01") == [["type", "date"], ["fuel", "2026-01-01"]])
    }

    @Test func escapesOnlyWhenNeeded() {
        #expect(CSV.line(["plain", "a,b", "q\"q", ""]) == "plain,\"a,b\",\"q\"\"q\",")
    }
}

@MainActor
struct RecordCSVTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private let header = "type,date,odometer,gallons,total_cost,full_tank,station,service,parts,next_due_odometer,next_due_date,notes"

    @Test func roundTripsFuelAndServices() {
        let fuel = [
            RecordCSV.FuelRow(date: date(2026, 8, 21), odometer: 54_586, gallons: 10.808, totalCost: 63.78,
                              isFullTank: true, station: "Costco, Main St", notes: "Gas light came on"),
            RecordCSV.FuelRow(date: date(2026, 7, 27), odometer: 53_720, gallons: 10.145, totalCost: 0,
                              isFullTank: false, station: nil, notes: nil),
        ]
        let services = [
            RecordCSV.ServiceRow(date: date(2026, 9, 2), odometer: 55_190, serviceType: "Oil change", cost: 48.5,
                                 parts: [.init(name: "Oil filter", cost: 9.99), .init(name: "Drain plug gasket", cost: 0)],
                                 nextDueOdometer: 60_190, nextDueDate: date(2027, 3, 2), notes: "Said \"looks good\""),
        ]
        let text = RecordCSV.encode(fuel: fuel, services: services, calendar: calendar)
        #expect(text.hasPrefix(header + "\n"))

        let parsed = RecordCSV.decode(text, calendar: calendar)
        #expect(parsed.problems.isEmpty)
        #expect(parsed.fuel == fuel.sorted { $0.odometer < $1.odometer })
        #expect(parsed.services == services)
    }

    @Test func blankCostMeansUnknown() {
        let parsed = RecordCSV.decode("\(header)\nfuel,2026-07-27,53720,10.145,,yes,,,,,,", calendar: calendar)
        #expect(parsed.fuel.first?.totalCost == 0)
        #expect(parsed.fuel.first?.isFullTank == true)
    }

    @Test func acceptsHandwrittenDatesAndAnyColumnOrder() {
        let parsed = RecordCSV.decode("date,odometer,type,gallons\n8/31/26,\"55,171\",Fuel,10.227", calendar: calendar)
        #expect(parsed.problems.isEmpty)
        #expect(parsed.fuel.first?.date == date(2026, 8, 31))
        #expect(parsed.fuel.first?.odometer == 55_171)
    }

    @Test func reportsBadRowsAndKeepsGoodOnes() {
        let text = """
        \(header)
        fuel,2026-13-01,1000,10,,yes,,,,,,
        fuel,2026-01-01,abc,10,,yes,,,,,,
        fuel,2026-01-01,1000,,,yes,,,,,,
        service,2026-01-01,1000,,,,,,,,,
        service,2026-01-01,1000,,,,,Oil change,Filter=cheap,,,
        refuel,2026-01-01,1000,10,,,,,,,,
        fuel,2026-01-02,1300,10,35,yes,,,,,,
        """
        let parsed = RecordCSV.decode(text, calendar: calendar)
        #expect(parsed.problems.map(\.row) == [2, 3, 4, 5, 6, 7])
        #expect(parsed.fuel.count == 1)
    }

    @Test func rejectsFileWithoutRequiredColumns() {
        let parsed = RecordCSV.decode("name,amount\nfoo,1", calendar: calendar)
        #expect(parsed.problems.count == 1)
        #expect(parsed.problems.first?.message.contains("Missing") == true)
        #expect(parsed.fuel.isEmpty && parsed.services.isEmpty)
    }

    @Test func skipsDuplicatesAgainstLogAndWithinFile() {
        let text = """
        \(header)
        fuel,2026-08-31,55171,10.227,61.35,yes,,,,,,
        fuel,2026-09-08,55448,11.043,68.46,yes,,,,,,
        fuel,2026-09-08,55448,11.043,68.46,yes,,,,,,
        service,2026-09-02,55190,,48.50,,,Oil change,,,,
        service,2026-09-02,55190,,,,,Tire rotation,,,,
        """
        let parsed = RecordCSV.decode(text, calendar: calendar)
        let plan = RecordCSV.newRows(
            parsed,
            existingFuelOdometers: [55_171],
            existingServiceKeys: [RecordCSV.serviceKey(date: date(2026, 9, 2), odometer: 55_190, type: "oil CHANGE", calendar: calendar)],
            calendar: calendar
        )
        #expect(plan.fuel.map(\.odometer) == [55_448])
        #expect(plan.services.map(\.serviceType) == ["Tire rotation"])
        #expect(plan.duplicates == 3)
    }
}

@MainActor
struct UnknownCostStatsTests {
    @Test func unknownCostsAreLeftOutOfSpendAndPrice() {
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        func entry(_ odometer: Int, cost: Double) -> FuelStats.Entry {
            .init(date: day, odometer: odometer, gallons: 10, totalCost: cost, isFullTank: true)
        }
        let stats = FuelStats(entries: [
            entry(1_000, cost: 0),
            entry(1_300, cost: 0),
            entry(1_600, cost: 40),
        ], today: day)
        #expect(stats.unknownCostCount == 2)
        #expect(stats.totalSpend == 40)
        #expect(stats.averagePricePerGallon == 4)
        // Unknown 1,300 fill counted at the $4 average: (40 + 40) / 600 mi.
        #expect(stats.costPerMile == 80.0 / 600.0)
    }
}

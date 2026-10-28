//
//  RecordImportTests.swift
//  DipstickTests
//

import Foundation
import Testing
@testable import Dipstick

struct RecordImportTests {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> String { String(format: "%04d-%02d-%02d", y, m, d) }

    @Test func readsDatesTheWaysTheyreWritten() {
        let cases = [
            "2017-08-08": day(2017, 8, 8), "8/8/2017": day(2017, 8, 8), "08/08/17": day(2017, 8, 8),
            "8-8-2017": day(2017, 8, 8), "Aug 8, 2017": day(2017, 8, 8), "August 8th 2017": day(2017, 8, 8),
            "8 Aug 2017": day(2017, 8, 8), "08-AUG-17": day(2017, 8, 8), "25/12/2019": day(2019, 12, 25),
        ]
        for (text, expected) in cases {
            #expect(FlexibleDate.parse(text).map(FlexibleDate.key) == expected, "\(text)")
        }
        #expect(FlexibleDate.parse("2/30/2017") == nil)
        #expect(FlexibleDate.parse("Part 15400-PLM-A02") == nil)
        #expect(FlexibleDate.all(in: "Date 11/29/2016  promised 12/1/2016").count == 2)
    }

    @Test func namesServicesTheAppsWay() {
        #expect(RecordImport.serviceNames(in: "REPLACE ENGINE OIL AND FILTER, ROTATE TIRES") == ["Oil change", "Tire rotation"])
        #expect(RecordImport.serviceNames(in: "Passed emissions inspection") == ["Smog check"])
        #expect(RecordImport.serviceNames(in: "Replace cabin air filter") == ["Cabin air filter"])
        #expect(RecordImport.serviceNames(in: "LOF") == ["Oil change"])
        #expect(RecordImport.serviceNames(in: "Heater blower transistor replaced") == ["Heater blower transistor"])
        #expect(RecordImport.serviceNames(in: "REPLACE WIPER BLADES", known: ["Wiper Blades"]) == ["Wiper Blades"])
        #expect(RecordImport.serviceNames(in: "Front struts") == ["Front struts"])
    }

    @Test func splitsWorkLeavesOutDeclinedAndMadeUpParts() {
        let services = RecordImport.services(
            raw: "Oil and filter changed", price: 49.95,
            parts: [.init(name: "OIL FILTER", cost: 7.5, partNumber: "15400-PLM-A02"),
                    .init(name: "Oil filter", cost: 7.5),
                    .init(name: "Oil", cost: 0)],
            notes: "Tires rotated. Tread 8/32. N/A")
        #expect(services.map(\.name) == ["Oil change", "Tire rotation"])
        #expect(services[0].price == 49.95)
        #expect(services[0].parts.map(\.name) == ["Oil filter"])
        #expect(services[0].notes == "Tread 8/32")
        #expect(RecordImport.services(raw: "Replace wiper blades (declined)", price: 39.95, parts: [], notes: nil).isEmpty)
        #expect(RecordImport.services(raw: "Wiper blades", price: nil, parts: [], notes: "Recommended at next visit").isEmpty)
    }

    @Test func flagsValuesNotOnThePage() {
        let page = "INVOICE DATE 08/08/2017   MILEAGE IN 18,967\nOIL CHANGE 65.00\nTOTAL 249.95"
        var visit = RecordImport.Visit(date: FlexibleDate.parse("8/8/2017"), odometer: 18_967, total: 249.95,
                                       services: [.init(name: "Oil change", price: 65), .init(name: "Brake fluid", price: 107.35)])
        RecordImport.check(&visit, against: .init(page))
        #expect(visit.unsure.isEmpty)
        #expect(visit.services.map(\.priceUnsure) == [false, true])

        var madeUp = RecordImport.Visit(date: FlexibleDate.parse("1/10/2024"), odometer: 10_000, services: [.init(name: "Oil change")])
        RecordImport.check(&madeUp, against: .init(page))
        #expect(madeUp.unsure == [.date, .odometer])
        #expect(RecordImport.isUnfounded(madeUp))
        #expect(!RecordImport.isUnfounded(visit))
    }

    @Test func findsMileageOnTheDatesLine() {
        let page = "Date        Mileage     Source\n06/10/2017  17,162      Clear Blue Test Only\n11/29/2017  20297  Acura"
        var visit = RecordImport.Visit(date: FlexibleDate.parse("6/10/2017"), services: [.init(name: "Smog check")])
        RecordImport.fillMissingMileage(&visit, pageText: page)
        #expect(visit.odometer == 17_162)
        #expect(visit.unsure.contains(.odometer))
        var other = RecordImport.Visit(date: FlexibleDate.parse("11/29/2017"), services: [.init(name: "x")])
        RecordImport.fillMissingMileage(&other, pageText: page)
        #expect(other.odometer == 20_297)
    }

    @Test func mergesRepeatsSortsAndChecksMileageOrder() {
        let a = RecordImport.Visit(date: FlexibleDate.parse("1/5/2020"), odometer: 30_000,
                                   services: [.init(name: "Oil change")], unsure: [.total])
        let b = RecordImport.Visit(date: FlexibleDate.parse("1/5/2020"), odometer: nil,
                                   services: [.init(name: "Oil change"), .init(name: "Tire rotation")], unsure: [.odometer])
        let early = RecordImport.Visit(date: FlexibleDate.parse("6/1/2019"), odometer: 25_000, services: [.init(name: "x")])
        let typo = RecordImport.Visit(date: FlexibleDate.parse("3/1/2021"), odometer: 3_500, services: [.init(name: "y")])
        let later = RecordImport.Visit(date: FlexibleDate.parse("9/1/2021"), odometer: 36_000, services: [.init(name: "z")])
        let tidy = RecordImport.tidy([a, b, later, early, typo])
        #expect(tidy.map(\.odometer) == [25_000, 30_000, 3_500, 36_000])
        #expect(tidy[1].services.map(\.name) == ["Oil change", "Tire rotation"])
        #expect(tidy[1].unsure.isEmpty)
        #expect(tidy[2].unsure.contains(.odometer))
        #expect(!tidy[3].unsure.contains(.odometer))
    }

    @Test func marksServicesAlreadyLogged() {
        var visits = [RecordImport.Visit(date: FlexibleDate.parse("8/8/2017"), odometer: 18_967,
                                         services: [.init(name: "Oil change"), .init(name: "Brake fluid")])]
        RecordImport.markDuplicates(&visits, existing: [(FlexibleDate.parse("8/9/2017")!, "oil change")])
        #expect(visits[0].services.map(\.isDuplicate) == [true, false])
        #expect(visits[0].services.map(\.include) == [false, true])
    }

    @Test func sharesTaxAndFeesAmongPricedServices() {
        let visit = RecordImport.Visit(date: FlexibleDate.parse("8/8/2017"), odometer: 18_967, shop: "Acura of Pleasanton",
                                       invoice: "ACCS179164", total: 249.95,
                                       services: [.init(name: "Oil change", price: 100), .init(name: "Tire rotation"),
                                                  .init(name: "Brake fluid", price: 120)])
        let rows = RecordImport.rows(for: visit)
        #expect(rows.map(\.serviceType) == ["Oil change", "Tire rotation", "Brake fluid"])
        #expect(rows.map(\.cost) == [113.61, 0, 136.34])
        #expect(abs(rows.reduce(0) { $0 + $1.cost } - 249.95) < 0.001)
        #expect(rows[0].notes == "Acura of Pleasanton; invoice ACCS179164; includes $13.61 tax and fees")
        #expect(rows.allSatisfy { $0.odometer == 18_967 })
    }

    @Test func putsAVisitOnlyTotalOnTheFirstService() {
        var visit = RecordImport.Visit(date: FlexibleDate.parse("11/29/2016"), odometer: 13_232, total: 841.66,
                                       services: [.init(name: "Oil change"), .init(name: "Brake pads")])
        var rows = RecordImport.rows(for: visit)
        #expect(rows.map(\.cost) == [841.66, 0])
        #expect(rows[0].notes == "whole-visit total, also covers Brake pads")
        #expect(rows[1].notes == "cost included in Oil change")

        visit.services[0].include = false
        rows = RecordImport.rows(for: visit)
        #expect(rows.map(\.serviceType) == ["Brake pads"])
        #expect(rows[0].cost == 841.66)

        visit.odometer = nil
        #expect(RecordImport.rows(for: visit).isEmpty)
    }

    @Test func splitsAListIntoVisitsButNotAnInvoice() {
        let list = """
            Service History
            Date        Mileage     Comments
            11/29/2016  13,232      Oil and filter changed
                                    Brake fluid flushed
            12/30/2016  14,039      Four tires replaced
            """
        let blocks = RecordImport.visitBlocks(list)
        #expect(blocks?.count == 2)
        #expect(blocks?[0].contains("Brake fluid flushed") == true)
        #expect(blocks?[1].hasPrefix("Service History\nDate") == true)

        let invoice = "REPAIR ORDER 123   INVOICE DATE 08/08/2017\nPROMISED 08/09/2017\nOIL CHANGE 65.00"
        #expect(RecordImport.visitBlocks(invoice) == nil)
    }

    @Test func readsAListWithoutTheLanguageModel() {
        let lines = ["Date  Mileage  Comments", "11/29/2016  13,232  Oil and filter changed", "Brake fluid flushed",
                     "12/30/2016  14,039  Four tires replaced", "Alignment performed", "06/10/2017 17,162 Recommended: wiper blades"]
        let visits = RecordImport.visitsByRules(lines: lines, page: 0)
        #expect(visits.map(\.odometer) == [13_232, 14_039])
        #expect(visits.map { $0.services.map(\.name) } == [["Oil change", "Brake fluid"], ["Tires", "Alignment"]])
    }

    @Test func readsAnyStyleOfSpreadsheet() throws {
        let csv = """
            Service Date,Miles,Work Performed,Price,Shop
            03/14/2021,"45,210",Oil & filter,$49.99,Jiffy Lube
            03/14/2021,"45,210",Rotate tires,$19.99,Jiffy Lube
            2022-01-02,51000,New battery,189.00,Costco
            """
        let visits = try #require(RecordImport.visits(fromCSV: csv))
        #expect(visits.count == 2)
        #expect(visits[0].odometer == 45_210)
        #expect(visits[0].shop == "Jiffy Lube")
        #expect(visits[0].services.map(\.name) == ["Oil change", "Tire rotation"])
        #expect(visits[0].services.map(\.price) == [49.99, 19.99])
        #expect(visits[1].services.map(\.name) == ["Battery"])
        #expect(RecordImport.visits(fromCSV: "a,b\n1,2") == nil)
    }

    @Test func turnsAnswersIntoNumbers() {
        #expect(RecordReader.wholeNumber("18,967 mi") == 18_967)
        #expect(RecordReader.wholeNumber("") == nil)
        #expect(RecordReader.amount("$1,234.56") == 1_234.56)
        #expect(RecordReader.amount("no charge") == nil)
        #expect(RecordReader.chunks(String(repeating: "line of text\n", count: 600), limit: 1_000).count == 8)
    }

    @Test func checksTheReadersServicesAgainstThePage() {
        let page = """
            LINE A 20K SERVICE - REPLACE ENGINE OIL AND FILTER, ROTATE TIRES  65.00
            PARTS: 15400-PLM-A02 OIL FILTER 1 @ 7.50  7.50
            LINE B BRAKE FLUID FLUSH  107.35
            LINE C FUEL SYSTEM CLEANER  20.00
            """
        var visit = RecordImport.Visit(date: nil, odometer: nil, services: [
            .init(name: "20K Service", price: 65,
                  parts: [.init(name: "Engine oil and filter", cost: 7.5, partNumber: "15400-PLM-A02"),
                          .init(name: "Transmission fluid", cost: 3, partNumber: "MAXLIFE 5W-20")]),
            .init(name: "Coolant", price: 107.35),
            .init(name: "Fuel system cleaner", price: 20),
        ])
        RecordImport.reconcile(&visit, source: page)
        #expect(visit.services.map(\.name) == ["Oil change", "Tire rotation", "Fuel system cleaner", "Brake fluid"])
        #expect(visit.services[0].price == 65)
        // Named as the page names it; a part not on the page is dropped.
        #expect(visit.services[0].parts.map(\.name) == ["Oil filter"])
        #expect(visit.services[0].parts.map(\.partNumber) == ["15400-PLM-A02"])
        #expect(visit.services[3].price == 107.35)
        #expect(visit.services.filter(\.nameUnsure).isEmpty)

        var madeUp = RecordImport.Visit(services: [.init(name: "Timing belt")])
        RecordImport.reconcile(&madeUp, source: "OIL CHANGE 49.99")
        #expect(madeUp.services.map(\.name) == ["Oil change"])
    }
}

//
//  MPGCalculatorTests.swift
//  DipstickTests
//

import Testing
@testable import Dipstick

@MainActor
struct MPGCalculatorTests {
    private typealias Fill = MPGCalculator.Fill<String>

    private func fill(_ id: String, _ odometer: Int, _ gallons: Double, full: Bool = true) -> Fill {
        Fill(id: id, odometer: odometer, gallons: gallons, isFullTank: full)
    }

    @Test func firstFillHasNoMPG() {
        let results = MPGCalculator.results(for: [fill("a", 1_000, 10)])
        #expect(results.isEmpty)
    }

    @Test func consecutiveFullTanks() {
        let results = MPGCalculator.results(for: [
            fill("a", 1_000, 12),
            fill("b", 1_300, 10),
        ])
        #expect(results["a"] == nil)
        #expect(results["b"] == .init(miles: 300, gallons: 10))
        #expect(results["b"]?.mpg == 30)
    }

    @Test func partialsAddGallonsToNextFullTank() {
        let results = MPGCalculator.results(for: [
            fill("a", 1_000, 12),
            fill("p1", 1_100, 3, full: false),
            fill("p2", 1_200, 2, full: false),
            fill("b", 1_400, 5),
        ])
        #expect(results["p1"] == nil)
        #expect(results["p2"] == nil)
        #expect(results["b"] == .init(miles: 400, gallons: 10))
    }

    @Test func partialsBeforeFirstFullTankAreIgnored() {
        let results = MPGCalculator.results(for: [
            fill("p", 900, 4, full: false),
            fill("a", 1_000, 12),
            fill("b", 1_250, 10),
        ])
        #expect(results.count == 1)
        #expect(results["b"] == .init(miles: 250, gallons: 10))
    }

    @Test func entriesOutOfOrderAreSortedByOdometer() {
        let results = MPGCalculator.results(for: [
            fill("c", 1_600, 10),
            fill("a", 1_000, 12),
            fill("b", 1_300, 10),
        ])
        #expect(results["b"] == .init(miles: 300, gallons: 10))
        #expect(results["c"] == .init(miles: 300, gallons: 10))
        #expect(results["a"] == nil)
    }

    @Test func equalOdometerGetsNoMPG() {
        let results = MPGCalculator.results(for: [
            fill("a", 1_000, 12),
            fill("b", 1_000, 1),
            fill("c", 1_300, 10),
        ])
        // The repeated reading yields zero miles, so it gets no MPG, but the
        // next tank still measures from it.
        #expect(results.values.allSatisfy { $0.miles > 0 })
        #expect(results["c"] == .init(miles: 300, gallons: 10))
    }

    @Test func averageWeightsByMilesAndGallons() {
        let average = MPGCalculator.average(of: [
            .init(miles: 300, gallons: 10), // 30 mpg
            .init(miles: 100, gallons: 10), // 10 mpg
        ])
        #expect(average == 20) // 400 mi / 20 gal, not the mean of 30 and 10
        #expect(MPGCalculator.average(of: []) == nil)
    }
}

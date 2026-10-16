//
//  CityHighwayMPGTests.swift
//  DipstickTests
//

import Foundation
import Testing
@testable import Dipstick

@MainActor
struct CityHighwayMPGTests {
    private typealias Model = CityHighwayMPG
    private let day0 = Date(timeIntervalSince1970: 1_790_000_000)
    private func day(_ n: Double) -> Date { day0 + n * 86_400 }

    /// Tanks for a car that really gets `city`/`highway` MPG, with the given
    /// highway fractions, 260 miles each, fully recorded.
    private func simulatedTanks(city: Double, highway: Double, fractions: [Double]) -> [Model.TrackedTank] {
        fractions.enumerated().map { i, fraction in
            let hwy = 260 * fraction, cty = 260 - hwy
            return Model.TrackedTank(start: day(Double(i * 7)), end: day(Double(i * 7 + 7)), miles: 260,
                                     gallons: cty / city + hwy / highway, recordedMiles: 260, highwayFraction: fraction)
        }
    }

    // MARK: Matching trips to tanks

    @Test func tripsBetweenFullFillUpsMakeATrackedTank() {
        let fills = [
            Model.Fill(date: day(0), odometer: 56_482, gallons: 9.768, isFullTank: true),
            Model.Fill(date: day(9), odometer: 56_742, gallons: 9.5, isFullTank: true),
        ]
        let trips = [
            Model.TripMiles(start: day(-1), cityMiles: 50, highwayMiles: 0),   // before: previous tank
            Model.TripMiles(start: day(1), cityMiles: 100, highwayMiles: 20),
            Model.TripMiles(start: day(4), cityMiles: 30, highwayMiles: 100),
            Model.TripMiles(start: day(10), cityMiles: 40, highwayMiles: 0),   // after: next tank
        ]
        let tanks = Model.trackedTanks(fills: fills, trips: trips)
        #expect(tanks.count == 1)
        #expect(tanks.first?.miles == 260)
        #expect(tanks.first?.recordedMiles == 250)
        #expect(abs((tanks.first?.highwayFraction ?? 0) - 0.48) < 0.0001)
        #expect(tanks.first?.highwayMiles == 260 * 0.48)  // scaled to odometer miles
    }

    @Test func partiallyRecordedTankIsLeftOut() {
        let fills = [
            Model.Fill(date: day(0), odometer: 1_000, gallons: 10, isFullTank: true),
            Model.Fill(date: day(7), odometer: 1_300, gallons: 10, isFullTank: true),
        ]
        let trips = [Model.TripMiles(start: day(1), cityMiles: 150, highwayMiles: 50)]  // 67% of 300
        #expect(Model.trackedTanks(fills: fills, trips: trips).isEmpty)
    }

    @Test func partialFillAddsGallonsToTheTank() {
        let fills = [
            Model.Fill(date: day(0), odometer: 1_000, gallons: 10, isFullTank: true),
            Model.Fill(date: day(3), odometer: 1_100, gallons: 3, isFullTank: false),
            Model.Fill(date: day(7), odometer: 1_300, gallons: 8, isFullTank: true),
        ]
        let trips = [Model.TripMiles(start: day(1), cityMiles: 150, highwayMiles: 150)]
        #expect(Model.trackedTanks(fills: fills, trips: trips).first?.gallons == 11)
    }

    @Test func currentTankProgress() {
        let fills = [Model.Fill(date: day(0), odometer: 56_482, gallons: 9.768, isFullTank: true)]
        let trips = [
            Model.TripMiles(start: day(-2), cityMiles: 99, highwayMiles: 99),
            Model.TripMiles(start: day(1), cityMiles: 50, highwayMiles: 30),
            Model.TripMiles(start: day(2), cityMiles: 4, highwayMiles: 0),
        ]
        let current = Model.currentTank(fills: fills, trips: trips)
        #expect(current?.recordedMiles == 84)
        #expect(abs((current?.highwayFraction ?? 0) - 30.0 / 84) < 0.0001)
    }

    // MARK: Estimating

    @Test func oneTankFitsItsGallonsUsingTheRuleOfThumb() throws {
        let tanks = simulatedTanks(city: 23, highway: 31, fractions: [0.35])
        let estimate = try #require(Model.estimate(from: tanks))
        let tank = tanks[0]
        // Explains the tank's gallons exactly…
        #expect(abs(tank.cityMiles / estimate.cityMPG + tank.highwayMiles / estimate.highwayMPG - tank.gallons) < 0.01)
        // …with the typical ratio, and is flagged rough.
        #expect(abs(estimate.highwayMPG / estimate.cityMPG - Model.typicalHighwayToCityRatio) < 0.01)
        #expect(estimate.isRough)
        #expect(abs(estimate.combinedMPG - tank.mpg) < 0.0001)
    }

    @Test func variedTanksRecoverTheRealNumbers() throws {
        // A car whose real ratio (1.5) differs from the rule of thumb.
        let tanks = simulatedTanks(city: 22, highway: 33, fractions: [0.1, 0.3, 0.5, 0.7, 0.9, 0.2, 0.6, 0.8])
        let estimate = try #require(Model.estimate(from: tanks))
        #expect(abs(estimate.cityMPG - 22) < 0.6)
        #expect(abs(estimate.highwayMPG - 33) < 0.6)
        #expect(!estimate.isRough)
        #expect(estimate.tankCount == 8)
    }

    @Test func similarMixesStayRough() throws {
        let tanks = simulatedTanks(city: 23, highway: 31, fractions: [0.34, 0.36, 0.35, 0.33])
        #expect(try #require(Model.estimate(from: tanks)).isRough)
    }

    @Test func noisySimilarTanksStayReasonable() throws {
        // Real fill-ups vary a few percent; similar mixes shouldn't give wild numbers.
        var tanks = simulatedTanks(city: 23, highway: 31, fractions: [0.34, 0.38, 0.31, 0.36])
        let noise = [1.04, 0.96, 1.03, 0.97]
        tanks = zip(tanks, noise).map { tank, n in
            Model.TrackedTank(start: tank.start, end: tank.end, miles: tank.miles, gallons: tank.gallons * n,
                              recordedMiles: tank.recordedMiles, highwayFraction: tank.highwayFraction)
        }
        let estimate = try #require(Model.estimate(from: tanks))
        #expect((15...35).contains(estimate.cityMPG))
        #expect((20...45).contains(estimate.highwayMPG))
        #expect(estimate.highwayMPG > estimate.cityMPG)
        #expect(estimate.isRough)
    }

    @Test func noTanksNoEstimate() {
        #expect(Model.estimate(from: []) == nil)
    }
}

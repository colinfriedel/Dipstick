//
//  CityHighwayMPG.swift
//  Dipstick
//

import Foundation
import SwiftData

/// City and highway MPG from full tanks whose drives were recorded.
///
/// Each tracked tank gives one equation: gallons = city miles / cityMPG +
/// highway miles / highwayMPG. Tanks with different city/highway mixes pin
/// down both numbers; one tank alone can't. Until there's enough variety, a
/// rule of thumb (highway ≈ 30% better than city) fills in what the data
/// can't decide, weighted lightly so real tanks quickly outweigh it.
enum CityHighwayMPG {
    /// A tank counts only if recorded trips cover this share of its miles.
    static let minimumCoverage = 0.8
    /// Trips can read a little long vs. the odometer; beyond this, something's off.
    static let maximumCoverage = 1.2
    /// Rule of thumb for gas cars: highway MPG ÷ city MPG.
    static let typicalHighwayToCityRatio = 1.3
    /// How many tanks' worth of weight the rule of thumb gets. With one tank
    /// any weight gives the same answer; 0.1 lets real tanks take over quickly
    /// without noisy, similar-mix tanks swinging the estimate (simulated with
    /// ±4% gallon noise).
    static let ruleOfThumbWeight = 0.1
    /// Fewer tanks than this, or too little variety in mix, is a rough estimate.
    static let solidTankCount = 3
    static let solidMixSpread = 0.1

    struct Fill {
        let date: Date
        let odometer: Int
        let gallons: Double
        let isFullTank: Bool
    }

    struct TripMiles {
        let start: Date
        let cityMiles: Double
        let highwayMiles: Double
        var totalMiles: Double { cityMiles + highwayMiles }
    }

    struct TrackedTank: Equatable {
        let start: Date
        let end: Date
        /// Odometer miles for the tank.
        let miles: Int
        let gallons: Double
        let recordedMiles: Double
        let highwayFraction: Double
        var coverage: Double { recordedMiles / Double(miles) }
        /// The tank's odometer miles split by the recorded mix.
        var cityMiles: Double { Double(miles) * (1 - highwayFraction) }
        var highwayMiles: Double { Double(miles) * highwayFraction }
        var mpg: Double { Double(miles) / gallons }
    }

    struct CurrentTank: Equatable {
        /// The last full fill-up.
        let since: Date
        let recordedMiles: Double
        let highwayFraction: Double?
    }

    struct Estimate: Equatable {
        let cityMPG: Double
        let highwayMPG: Double
        /// Measured: total miles ÷ total gallons of the tracked tanks.
        let combinedMPG: Double
        let tankCount: Int
        /// Share of tracked miles on the highway.
        let highwayShare: Double
        /// Too few tanks, or mixes too similar, for the data alone to decide.
        let isRough: Bool
    }

    // MARK: Tanks

    /// Full tanks (previous full fill-up → this one) with their recorded trips.
    /// Partial fills add gallons to the next full tank, as in `MPGCalculator`.
    /// Only tanks whose trips cover enough of their miles are returned.
    static func trackedTanks(fills: [Fill], trips: [TripMiles]) -> [TrackedTank] {
        let sorted = fills.sorted { $0.odometer < $1.odometer }
        var tanks: [TrackedTank] = []
        var previousFull: Fill?
        var gallons = 0.0

        for fill in sorted {
            guard let previous = previousFull else {
                if fill.isFullTank { previousFull = fill }
                continue
            }
            gallons += fill.gallons
            guard fill.isFullTank else { continue }
            defer {
                previousFull = fill
                gallons = 0
            }

            let miles = fill.odometer - previous.odometer
            guard miles > 0, gallons > 0, fill.date > previous.date else { continue }
            let inTank = trips.filter { $0.start >= previous.date && $0.start < fill.date }
            let recorded = inTank.reduce(0) { $0 + $1.totalMiles }
            let coverage = recorded / Double(miles)
            guard (minimumCoverage...maximumCoverage).contains(coverage) else { continue }

            let highway = inTank.reduce(0) { $0 + $1.highwayMiles }
            tanks.append(TrackedTank(
                start: previous.date, end: fill.date, miles: miles, gallons: gallons,
                recordedMiles: recorded, highwayFraction: highway / recorded
            ))
        }
        return tanks
    }

    /// Recording progress since the last full fill-up.
    static func currentTank(fills: [Fill], trips: [TripMiles]) -> CurrentTank? {
        guard let lastFull = fills.filter(\.isFullTank).max(by: { $0.odometer < $1.odometer }) else { return nil }
        let since = trips.filter { $0.start >= lastFull.date }
        let recorded = since.reduce(0) { $0 + $1.totalMiles }
        let highway = since.reduce(0) { $0 + $1.highwayMiles }
        return CurrentTank(since: lastFull.date, recordedMiles: recorded,
                           highwayFraction: recorded > 0 ? highway / recorded : nil)
    }

    // MARK: Estimate

    /// Solves for city and highway MPG by least squares on gallons, with the
    /// rule of thumb as a light extra nudge. Nil without tracked tanks.
    static func estimate(from tanks: [TrackedTank]) -> Estimate? {
        guard !tanks.isEmpty else { return nil }
        // Unknowns: x = gallons per city mile, y = gallons per highway mile.
        var cc = 0.0, ch = 0.0, hh = 0.0, cg = 0.0, hg = 0.0, size = 0.0
        for tank in tanks {
            let c = tank.cityMiles, h = tank.highwayMiles, g = tank.gallons
            cc += c * c; ch += c * h; hh += h * h
            cg += c * g; hg += h * g
            size += c * c + h * h
        }
        // Rule of thumb: highway MPG = r × city MPG, i.e. x = r·y, added as
        // penalty λ(x − r·y)² with λ a fraction of an average tank's size.
        let r = typicalHighwayToCityRatio
        let lambda = ruleOfThumbWeight * size / Double(tanks.count)
        let a = cc + lambda
        let b = ch - lambda * r
        let d = hh + lambda * r * r
        let determinant = a * d - b * b
        guard determinant > 0 else { return nil }
        let x = (d * cg - b * hg) / determinant
        let y = (a * hg - b * cg) / determinant
        guard x > 0, y > 0 else { return nil }

        let miles = tanks.reduce(0) { $0 + Double($1.miles) }
        let gallons = tanks.reduce(0) { $0 + $1.gallons }
        let highwayShare = tanks.reduce(0) { $0 + $1.highwayMiles } / miles
        let fractions = tanks.map(\.highwayFraction)
        let mean = fractions.reduce(0, +) / Double(fractions.count)
        let spread = (fractions.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(fractions.count)).squareRoot()

        return Estimate(
            cityMPG: 1 / x, highwayMPG: 1 / y, combinedMPG: miles / gallons,
            tankCount: tanks.count, highwayShare: highwayShare,
            isRough: tanks.count < solidTankCount || spread < solidMixSpread
        )
    }
}

extension Vehicle {
    private var cityHighwayInputs: (fills: [CityHighwayMPG.Fill], trips: [CityHighwayMPG.TripMiles]) {
        let fills = (fuelEntries ?? []).map {
            CityHighwayMPG.Fill(date: $0.date, odometer: $0.odometer, gallons: $0.gallons, isFullTank: $0.isFullTank)
        }
        let trips = (trips ?? [])
            .filter { $0.status == .assigned }
            .map { CityHighwayMPG.TripMiles(start: $0.startDate, cityMiles: $0.cityMiles, highwayMiles: $0.highwayMiles) }
        return (fills, trips)
    }

    var trackedTanks: [CityHighwayMPG.TrackedTank] {
        let inputs = cityHighwayInputs
        return CityHighwayMPG.trackedTanks(fills: inputs.fills, trips: inputs.trips)
    }

    var currentTankRecording: CityHighwayMPG.CurrentTank? {
        let inputs = cityHighwayInputs
        return CityHighwayMPG.currentTank(fills: inputs.fills, trips: inputs.trips)
    }
}

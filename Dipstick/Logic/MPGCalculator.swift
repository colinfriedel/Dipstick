//
//  MPGCalculator.swift
//  Dipstick
//

import Foundation
import SwiftData

/// Computes MPG between consecutive full-tank fill-ups.
///
/// Partial fills don't get their own MPG; their gallons are added to the next
/// full tank. Partials logged before the first full tank are ignored, since the
/// starting fuel level is unknown.
enum MPGCalculator {
    struct Fill<ID: Hashable> {
        let id: ID
        let odometer: Int
        let gallons: Double
        let isFullTank: Bool
    }

    struct Result: Equatable {
        let miles: Int
        let gallons: Double
        var mpg: Double { Double(miles) / gallons }
    }

    /// MPG for every full-tank fill that has a previous full tank to measure from.
    /// Fills without an entry (first fill, partials) aren't in the dictionary.
    static func results<ID>(for fills: [Fill<ID>]) -> [ID: Result] {
        // Always sort by odometer; insertion or date order can't be trusted.
        let sorted = fills.sorted { $0.odometer < $1.odometer }

        var results: [ID: Result] = [:]
        var previousFullOdometer: Int?
        var gallonsSincePreviousFull = 0.0

        for fill in sorted {
            guard fill.isFullTank else {
                if previousFullOdometer != nil {
                    gallonsSincePreviousFull += fill.gallons
                }
                continue
            }

            if let previous = previousFullOdometer {
                let miles = fill.odometer - previous
                let gallons = gallonsSincePreviousFull + fill.gallons
                if miles > 0, gallons > 0 {
                    results[fill.id] = Result(miles: miles, gallons: gallons)
                }
            }
            previousFullOdometer = fill.odometer
            gallonsSincePreviousFull = 0
        }
        return results
    }

    /// MPG of the most recent full tank (by odometer) that has one.
    static func latest<ID>(in fills: [Fill<ID>], results: [ID: Result]) -> Result? {
        fills
            .sorted { $0.odometer > $1.odometer }
            .lazy
            .compactMap { results[$0.id] }
            .first
    }

    /// Overall MPG across the given results: total miles / total gallons, so a
    /// long tank counts for more than a short one.
    static func average<S: Sequence>(of results: S) -> Double? where S.Element == Result {
        var miles = 0
        var gallons = 0.0
        for result in results {
            miles += result.miles
            gallons += result.gallons
        }
        return gallons > 0 ? Double(miles) / gallons : nil
    }
}

extension Vehicle {
    /// Last-tank and overall MPG, or nil until two full tanks are logged.
    var mpgSummary: (latest: Double?, average: Double?) {
        let fills = (fuelEntries ?? []).map(\.fill)
        let results = MPGCalculator.results(for: fills)
        return (
            MPGCalculator.latest(in: fills, results: results)?.mpg,
            MPGCalculator.average(of: results.values)
        )
    }
}

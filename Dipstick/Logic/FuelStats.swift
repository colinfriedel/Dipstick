//
//  FuelStats.swift
//  Dipstick
//

import Foundation
import SwiftData

/// Summary numbers and chart data for one vehicle's fuel log. Plain values in,
/// plain values out, so it's testable without SwiftData.
struct FuelStats {
    /// How many of the latest full tanks count as "recent".
    static let recentTankCount = 5

    struct Entry {
        let date: Date
        let odometer: Int
        let gallons: Double
        let totalCost: Double
        let isFullTank: Bool
    }

    /// One full tank that has an MPG (a point on the trend chart).
    struct Tank: Identifiable, Equatable {
        let date: Date
        let odometer: Int
        let result: MPGCalculator.Result
        var mpg: Double { result.mpg }
        var id: Int { odometer }
    }

    struct MonthSpend: Identifiable, Equatable {
        /// First instant of the month.
        let month: Date
        let total: Double
        var id: Date { month }
    }

    /// Full tanks with an MPG, oldest first by odometer.
    let tanks: [Tank]
    let averageMPG: Double?
    let recentMPG: Double?
    let best: Tank?
    let worst: Tank?

    let totalSpend: Double
    let totalGallons: Double
    let spendThisYear: Double
    /// From fill-ups with a known cost only.
    let averagePricePerGallon: Double?
    /// Fuel cost per mile driven between the first and latest fill-up. Fill-ups
    /// with an unknown cost are counted at the average price.
    let costPerMile: Double?
    /// Fill-ups with no recorded cost (left out of the spend totals).
    let unknownCostCount: Int
    /// The last 12 months including the current one, oldest first; months with
    /// no fill-ups are 0 so the chart has no gaps.
    let monthlySpend: [MonthSpend]

    init(entries: [Entry], today: Date = Date(), calendar: Calendar = .current) {
        let sorted = entries.sorted { $0.odometer < $1.odometer }

        // MPG, reusing the same calculator as the fuel log.
        let fills = sorted.enumerated().map { index, entry in
            MPGCalculator.Fill(id: index, odometer: entry.odometer, gallons: entry.gallons, isFullTank: entry.isFullTank)
        }
        let results = MPGCalculator.results(for: fills)
        tanks = sorted.indices.compactMap { index in
            results[index].map { Tank(date: sorted[index].date, odometer: sorted[index].odometer, result: $0) }
        }
        averageMPG = MPGCalculator.average(of: tanks.map(\.result))
        recentMPG = MPGCalculator.average(of: tanks.suffix(Self.recentTankCount).map(\.result))
        best = tanks.max { $0.mpg < $1.mpg }
        worst = tanks.min { $0.mpg < $1.mpg }

        // Spend. A cost of 0 means unknown, so it adds nothing to the totals
        // and is left out of the price.
        let known = sorted.filter { $0.totalCost > 0 }
        totalSpend = known.reduce(0) { $0 + $1.totalCost }
        totalGallons = sorted.reduce(0) { $0 + $1.gallons }
        unknownCostCount = sorted.count - known.count
        let knownGallons = known.reduce(0) { $0 + $1.gallons }
        averagePricePerGallon = knownGallons > 0 ? totalSpend / knownGallons : nil

        let thisYear = calendar.component(.year, from: today)
        spendThisYear = sorted
            .filter { calendar.component(.year, from: $0.date) == thisYear }
            .reduce(0) { $0 + $1.totalCost }

        // The first fill-up's fuel was burned before tracking started, so it
        // isn't part of the miles that follow.
        if let first = sorted.first, let last = sorted.last, last.odometer > first.odometer,
           let price = averagePricePerGallon {
            let cost = sorted.dropFirst().reduce(0) { $0 + ($1.totalCost > 0 ? $1.totalCost : $1.gallons * price) }
            costPerMile = cost / Double(last.odometer - first.odometer)
        } else {
            costPerMile = nil
        }

        // Monthly spend, last 12 months.
        let thisMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
        let months = (0..<12).reversed().compactMap {
            calendar.date(byAdding: .month, value: -$0, to: thisMonth)
        }
        var totals: [Date: Double] = [:]
        for entry in sorted {
            if let month = calendar.dateInterval(of: .month, for: entry.date)?.start {
                totals[month, default: 0] += entry.totalCost
            }
        }
        monthlySpend = months.map { MonthSpend(month: $0, total: totals[$0] ?? 0) }
    }
}

extension Vehicle {
    func fuelStats(today: Date = Date()) -> FuelStats {
        FuelStats(
            entries: (fuelEntries ?? []).map {
                .init(date: $0.date, odometer: $0.odometer, gallons: $0.gallons,
                      totalCost: $0.totalCost, isFullTank: $0.isFullTank)
            },
            today: today
        )
    }
}

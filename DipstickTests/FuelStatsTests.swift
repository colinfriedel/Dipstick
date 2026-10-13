//
//  FuelStatsTests.swift
//  DipstickTests
//

import Foundation
import Testing
@testable import Dipstick

@MainActor
struct FuelStatsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var today: Date { date(2026, 10, 12) }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func entry(
        _ odometer: Int, _ gallons: Double, cost: Double = 35,
        full: Bool = true, on day: Date? = nil
    ) -> FuelStats.Entry {
        .init(date: day ?? date(2026, 9, 1), odometer: odometer, gallons: gallons, totalCost: cost, isFullTank: full)
    }

    private func stats(_ entries: [FuelStats.Entry]) -> FuelStats {
        FuelStats(entries: entries, today: today, calendar: calendar)
    }

    @Test func emptyLogHasNoNumbers() {
        let s = stats([])
        #expect(s.tanks.isEmpty)
        #expect(s.averageMPG == nil)
        #expect(s.recentMPG == nil)
        #expect(s.totalSpend == 0)
        #expect(s.costPerMile == nil)
        #expect(s.averagePricePerGallon == nil)
        #expect(s.monthlySpend.count == 12)
    }

    @Test func averageBestAndWorst() {
        let s = stats([
            entry(1_000, 10),
            entry(1_300, 10),  // 30 mpg
            entry(1_500, 10),  // 20 mpg
        ])
        #expect(s.tanks.map(\.mpg) == [30, 20])
        #expect(s.averageMPG == 25)  // 500 mi / 20 gal
        #expect(s.best?.mpg == 30)
        #expect(s.worst?.mpg == 20)
    }

    @Test func recentUsesLastFiveTanksByOdometer() {
        // First tank 10 mpg, then five tanks at 30 mpg, logged out of order.
        var entries = [entry(0, 10), entry(100, 10)]
        for i in 1...5 { entries.append(entry(100 + i * 300, 10)) }
        let s = stats(entries.reversed())
        #expect(s.tanks.count == 6)
        #expect(s.recentMPG == 30)
        #expect(s.averageMPG == 1_600.0 / 60.0)
    }

    @Test func partialsFeedTheNextTank() {
        let s = stats([
            entry(1_000, 10),
            entry(1_100, 4, full: false),
            entry(1_400, 6),
        ])
        #expect(s.tanks.map(\.mpg) == [40])  // 400 mi / 10 gal
    }

    @Test func spendAndPrice() {
        let s = stats([
            entry(1_000, 10, cost: 30, on: date(2025, 12, 20)),
            entry(1_300, 10, cost: 40, on: date(2026, 1, 5)),
            entry(1_600, 10, cost: 50, on: date(2026, 9, 1)),
        ])
        #expect(s.totalSpend == 120)
        #expect(s.spendThisYear == 90)
        #expect(s.averagePricePerGallon == 4)
    }

    @Test func costPerMileSkipsFirstFill() {
        let s = stats([
            entry(1_000, 10, cost: 999),  // fuel burned before tracking started
            entry(1_300, 10, cost: 30),
            entry(1_500, 10, cost: 30),
        ])
        #expect(s.costPerMile == 60.0 / 500.0)
        #expect(stats([entry(1_000, 10)]).costPerMile == nil)
    }

    @Test func monthlySpendCoversLastTwelveMonthsWithZeros() {
        let s = stats([
            entry(1_000, 10, cost: 30, on: date(2026, 10, 2)),
            entry(1_300, 10, cost: 20, on: date(2026, 10, 9)),
            entry(1_600, 10, cost: 40, on: date(2026, 3, 15)),
            entry(1_900, 10, cost: 99, on: date(2025, 9, 30)),  // 13 months ago, excluded
        ])
        #expect(s.monthlySpend.count == 12)
        #expect(s.monthlySpend.first?.month == date(2025, 11, 1))
        #expect(s.monthlySpend.last?.month == date(2026, 10, 1))
        #expect(s.monthlySpend.last?.total == 50)
        #expect(s.monthlySpend.first { $0.month == date(2026, 3, 1) }?.total == 40)
        #expect(s.monthlySpend.reduce(0) { $0 + $1.total } == 90)
    }
}

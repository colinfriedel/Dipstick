import Foundation
import Testing
@testable import Dipstick

struct FuelStatsTests {

    private func entry(id: Int, year: Int, cost: Double, mpg: Double?) -> FuelEntry {
        FuelEntry(id: id, vehicleId: 1,
                  date: CalendarDate(year: year, month: 6, day: 1),
                  odometer: 1000 * id, gallons: 10, totalCost: cost,
                  isFullTank: mpg != nil, stationName: nil, notes: nil,
                  costPerGallon: cost / 10, mpg: mpg)
    }

    @Test func emptyStatsAreZeroAndNil() {
        let stats = FuelStats(entries: [])
        #expect(stats.fillUpCount == 0)
        #expect(stats.totalSpendAllTime == 0)
        #expect(stats.averageMPG == nil)
        #expect(stats.bestMPG == nil)
    }

    @Test func aggregatesSpendAndFiltersThisYear() {
        let entries = [
            entry(id: 1, year: 2023, cost: 40, mpg: nil),
            entry(id: 2, year: 2024, cost: 30, mpg: nil),
            entry(id: 3, year: 2024, cost: 35, mpg: nil),
        ]
        let stats = FuelStats(entries: entries, year: 2024)

        #expect(stats.fillUpCount == 3)
        #expect(stats.totalSpendAllTime == 105)
        #expect(stats.totalSpendThisYear == 65)
    }

    @Test func averageAndBestUseOnlyEntriesWithMPG() {
        let entries = [
            entry(id: 1, year: 2024, cost: 30, mpg: nil),   // ignored
            entry(id: 2, year: 2024, cost: 30, mpg: 30),
            entry(id: 3, year: 2024, cost: 30, mpg: 40),
        ]
        let stats = FuelStats(entries: entries, year: 2024)

        #expect(stats.averageMPG == 35)
        #expect(stats.bestMPG == 40)
    }
}

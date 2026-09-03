import Foundation

/// A small summary computed on the client from a vehicle's fuel entries.
///
/// The fuller stats screen — server-computed via `GET /vehicles/{id}/stats`, with
/// an MPG trend chart — is Milestone 9. This covers the headline numbers that
/// fall straight out of the data the Fuel tab already loaded.
struct FuelStats {
    var fillUpCount: Int
    var totalSpendAllTime: Double
    var totalSpendThisYear: Double
    /// Mean of the MPG values the backend was able to compute (full-tank intervals).
    var averageMPG: Double?
    var bestMPG: Double?

    init(entries: [FuelEntry], year: Int = Calendar.current.component(.year, from: .now)) {
        fillUpCount = entries.count
        totalSpendAllTime = entries.reduce(0) { $0 + $1.totalCost }
        totalSpendThisYear = entries
            .filter { $0.date.year == year }
            .reduce(0) { $0 + $1.totalCost }

        let mpgs = entries.compactMap(\.mpg)
        averageMPG = mpgs.isEmpty ? nil : mpgs.reduce(0, +) / Double(mpgs.count)
        bestMPG = mpgs.max()
    }
}

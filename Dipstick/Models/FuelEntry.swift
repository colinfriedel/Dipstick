//
//  FuelEntry.swift
//  Dipstick
//

import Foundation
import SwiftData

/// One fill-up. MPG isn't stored; it's derived by `MPGCalculator` from the
/// vehicle's full set of entries, so editing an old entry can't leave it stale.
@Model
final class FuelEntry {
    var date: Date = Date()
    var odometer: Int = 0
    var gallons: Double = 0
    var totalCost: Double = 0
    var isFullTank: Bool = true
    var station: String?
    var notes: String?
    var vehicle: Vehicle?

    init(
        date: Date = Date(),
        odometer: Int,
        gallons: Double,
        totalCost: Double,
        isFullTank: Bool = true,
        station: String? = nil,
        notes: String? = nil
    ) {
        self.date = date
        self.odometer = odometer
        self.gallons = gallons
        self.totalCost = totalCost
        self.isFullTank = isFullTank
        self.station = station
        self.notes = notes
    }

    var pricePerGallon: Double? {
        gallons > 0 ? totalCost / gallons : nil
    }

    /// The plain values `MPGCalculator` needs, keyed by this entry's identity.
    var fill: MPGCalculator.Fill<PersistentIdentifier> {
        .init(id: persistentModelID, odometer: odometer, gallons: gallons, isFullTank: isFullTank)
    }
}

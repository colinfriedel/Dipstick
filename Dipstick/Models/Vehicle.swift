//
//  Vehicle.swift
//  Dipstick
//

import Foundation
import SwiftData

/// A car being tracked. Every property has a default or is optional so the
/// model stays compatible with CloudKit sync when it's turned on later.
@Model
final class Vehicle {
    var name: String = ""
    var year: Int?
    var make: String?
    var model: String?
    var vin: String?
    var currentOdometer: Int = 0
    /// The car's CarPlay/Bluetooth connection (`CarConnection.id`), so trips
    /// started by connecting to it are assigned automatically.
    var connectionID: String?
    var connectionName: String?

    @Relationship(deleteRule: .cascade, inverse: \FuelEntry.vehicle)
    var fuelEntries: [FuelEntry]? = []

    @Relationship(deleteRule: .cascade, inverse: \MaintenanceEntry.vehicle)
    var maintenanceEntries: [MaintenanceEntry]? = []
    @Relationship(deleteRule: .cascade, inverse: \Trip.vehicle)
    var trips: [Trip]? = []

    init(
        name: String,
        year: Int? = nil,
        make: String? = nil,
        model: String? = nil,
        vin: String? = nil,
        currentOdometer: Int = 0
    ) {
        self.name = name
        self.year = year
        self.make = make
        self.model = model
        self.vin = vin
        self.currentOdometer = currentOdometer
    }

    /// Raise the odometer if a newly logged reading is higher. Never lowers it,
    /// so deleting or backfilling an old entry doesn't move it backwards.
    func recordOdometer(_ reading: Int) {
        if reading > currentOdometer {
            currentOdometer = reading
        }
    }

    /// "2014 Mazda Miata", built from whichever of year/make/model are set.
    var yearMakeModel: String {
        [year.map(String.init), make, model]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

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

    // fuelEntries and maintenanceEntries relationships are added in build steps 2 and 3.

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

    /// "2014 Mazda Miata", built from whichever of year/make/model are set.
    var yearMakeModel: String {
        [year.map(String.init), make, model]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

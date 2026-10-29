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
    /// Trim or sub-model: "Base", "Type S", "EX", "Si".
    var trim: String?
    var vin: String?
    var currentOdometer: Int = 0
    /// Chip color as "#RRGGBB"; nil shows a neutral chip.
    var colorHex: String?
    /// Optional paint name, e.g. "Redondo Red Pearl".
    var colorName: String?
    /// Every CarPlay/Bluetooth connection known to belong to this car, one per
    /// line as "id<TAB>name" (plain text so CloudKit can sync it). Use
    /// `connections` / `addConnection` instead. A car can have several, e.g.
    /// Bluetooth that connects first and CarPlay a moment later.
    var knownConnections: String = ""
    /// Single connection from before cars could have several; folded into
    /// `connections` and cleared when a connection is next added or removed.
    var connectionID: String?
    var connectionName: String?

    @Relationship(deleteRule: .cascade, inverse: \FuelEntry.vehicle)
    var fuelEntries: [FuelEntry]? = []

    @Relationship(deleteRule: .cascade, inverse: \MaintenanceEntry.vehicle)
    var maintenanceEntries: [MaintenanceEntry]? = []
    @Relationship(deleteRule: .cascade, inverse: \Trip.vehicle)
    var trips: [Trip]? = []
    /// Where the schedule came from: "standard" (the general one every new
    /// car starts with), "manual" (read from the owner's manual), a preset's
    /// name, or nil (built by hand).
    var scheduleSource: String?
    /// Factory maintenance schedule from the owner's manual.
    @Relationship(deleteRule: .cascade, inverse: \ScheduleItem.vehicle)
    var scheduleItems: [ScheduleItem]? = []
    @Relationship(deleteRule: .cascade, inverse: \TestEntry.vehicle)
    var testEntries: [TestEntry]? = []
    /// Notes and photos per service and test type.
    @Relationship(deleteRule: .cascade, inverse: \ReferencePage.vehicle)
    var referencePages: [ReferencePage]? = []

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

    /// "2004 Acura RSX Type S", built from whichever of year, make, model
    /// and trim are set.
    var yearMakeModel: String {
        [year.map(String.init), make, model, trim]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

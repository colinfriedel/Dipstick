//
//  MaintenanceEntry.swift
//  Dipstick
//

import Foundation
import SwiftData

/// One service done on a vehicle. `serviceType` is plain text so custom names
/// work and old records survive changes to the built-in list.
@Model
final class MaintenanceEntry {
    var date: Date = Date()
    var odometer: Int = 0
    var serviceType: String = ""
    /// Total paid: parts plus any labor or shop fees.
    var cost: Double = 0
    var notes: String?
    var nextDueOdometer: Int?
    var nextDueDate: Date?
    var vehicle: Vehicle?

    @Relationship(deleteRule: .cascade, inverse: \PartUsed.entry)
    var parts: [PartUsed]? = []

    init(
        date: Date = Date(),
        odometer: Int,
        serviceType: String,
        cost: Double = 0,
        notes: String? = nil,
        nextDueOdometer: Int? = nil,
        nextDueDate: Date? = nil
    ) {
        self.date = date
        self.odometer = odometer
        self.serviceType = serviceType
        self.cost = cost
        self.notes = notes
        self.nextDueOdometer = nextDueOdometer
        self.nextDueDate = nextDueDate
    }

    var sortedParts: [PartUsed] {
        (parts ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// A part used in a maintenance entry. A small model rather than a list of
/// strings so each part can carry its own cost.
@Model
final class PartUsed {
    var name: String = ""
    /// Price of one; the line costs `cost × quantity`.
    var cost: Double = 0
    /// Manufacturer part number, e.g. "08798-9008A".
    var partNumber: String?
    var quantity: Int = 1
    var entry: MaintenanceEntry?

    init(name: String, cost: Double = 0, partNumber: String? = nil, quantity: Int = 1) {
        self.name = name
        self.cost = cost
        self.partNumber = partNumber
        self.quantity = max(quantity, 1)
    }

    var lineTotal: Double { cost * Double(max(quantity, 1)) }

    /// "Brake fluid ×2", or just the name for one.
    var summary: String {
        quantity > 1 ? "\(name) ×\(quantity)" : name
    }
}

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
    /// Stays the same on every phone, for iCloud sync and sharing. Optional
    /// so existing records get their own (see `SyncIDs.assign`); a default
    /// would give them all the same one.
    var syncID: String?
    /// Who added it, on a shared car ("Mom"); nil for your own.
    var addedBy: String?
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

    /// Photos for next time (manual pages, the part, the receipt), shown with
    /// the notes whenever this service is logged again.
    @Relationship(deleteRule: .cascade, inverse: \ReferencePhoto.entry)
    var photos: [ReferencePhoto]? = []

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

    var sortedPhotos: [ReferencePhoto] {
        (photos ?? []).sorted { ($0.order, $0.addedAt) < ($1.order, $1.addedAt) }
    }

    /// True when there are notes or photos to show next time.
    var hasNotesOrPhotos: Bool {
        !(notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(photos ?? []).isEmpty
    }

    var sortedParts: [PartUsed] {
        (parts ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// A part used in a maintenance entry. A small model rather than a list of
/// strings so each part can carry its own cost.
@Model
final class PartUsed {
    /// Stays the same on every phone, for iCloud sync and sharing. Optional
    /// so existing records get their own (see `SyncIDs.assign`); a default
    /// would give them all the same one.
    var syncID: String?
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

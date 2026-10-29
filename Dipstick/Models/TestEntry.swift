//
//  TestEntry.swift
//  Dipstick
//

import Foundation
import SwiftData

/// A test or inspection done on a vehicle (compression, battery, pad
/// thickness…). `testType` is plain text so custom tests work; built-in
/// types and their fields are in `TestTemplate`.
@Model
final class TestEntry {
    /// Stays the same on every phone, for iCloud sync and sharing. Optional
    /// so existing records get their own (see `SyncIDs.assign`); a default
    /// would give them all the same one.
    var syncID: String?
    /// Who added it, on a shared car ("Mom"); nil for your own.
    var addedBy: String?
    var date: Date = Date()
    var odometer: Int = 0
    var testType: String = ""
    var notes: String?
    var vehicle: Vehicle?

    @Relationship(deleteRule: .cascade, inverse: \TestReading.entry)
    var readings: [TestReading]? = []

    init(date: Date = Date(), odometer: Int, testType: String, notes: String? = nil) {
        self.date = date
        self.odometer = odometer
        self.testType = testType
        self.notes = notes
    }

    var sortedReadings: [TestReading] {
        (readings ?? []).sorted { $0.order < $1.order }
    }
}

/// One measurement in a test: "Cylinder 1: 165 psi (wet 180)".
@Model
final class TestReading {
    /// Stays the same on every phone, for iCloud sync and sharing. Optional
    /// so existing records get their own (see `SyncIDs.assign`); a default
    /// would give them all the same one.
    var syncID: String?
    var label: String = ""
    var value: Double?
    /// A second reading for the same thing, e.g. wet compression.
    var secondValue: Double?
    var unit: String = ""
    /// A written result instead of (or as well as) a number: "Cracked".
    var text: String?
    var order: Int = 0
    var entry: TestEntry?

    init(label: String, value: Double? = nil, secondValue: Double? = nil, unit: String = "",
         text: String? = nil, order: Int = 0) {
        self.label = label
        self.value = value
        self.secondValue = secondValue
        self.unit = unit
        self.text = text
        self.order = order
    }
}

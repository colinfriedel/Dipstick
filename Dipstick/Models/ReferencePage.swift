//
//  ReferencePage.swift
//  Dipstick
//

import Foundation
import SwiftData

/// Notes and photos for doing a service or test next time (manual pages,
/// parts, reminders), one page per type per car. For tests it also holds the
/// spec from the manual and an optional reminder interval.
@Model
final class ReferencePage {
    /// "service" or "test".
    var kind: String = ReferencePage.serviceKind
    /// The service or test type it's for, as logged: "Brake fluid".
    var name: String = ""
    var notes: String = ""

    // Tests: the manual's spec, in the test's unit.
    var specMin: Double?
    var specMax: Double?
    /// Largest allowed difference between the highest and lowest reading
    /// (e.g. compression across cylinders).
    var specMaxSpread: Double?

    // Tests: how often to do it, if you want a reminder.
    var remindEveryMonths: Int?
    var remindEveryMiles: Int?

    var vehicle: Vehicle?

    @Relationship(deleteRule: .cascade, inverse: \ReferencePhoto.page)
    var photos: [ReferencePhoto]? = []

    static let serviceKind = "service"
    static let testKind = "test"

    init(kind: String, name: String) {
        self.kind = kind
        self.name = name
    }

    var sortedPhotos: [ReferencePhoto] {
        (photos ?? []).sorted { ($0.order, $0.addedAt) < ($1.order, $1.addedAt) }
    }

    var hasSpec: Bool { specMin != nil || specMax != nil || specMaxSpread != nil }

    var isEmpty: Bool {
        notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (photos ?? []).isEmpty && !hasSpec
            && remindEveryMonths == nil && remindEveryMiles == nil
    }
}

/// A photo on a reference page. Stored outside the database file
/// (`externalStorage`) so pages with many photos stay quick to load.
@Model
final class ReferencePhoto {
    @Attribute(.externalStorage) var data: Data?
    var caption: String?
    var addedAt: Date = Date()
    var order: Int = 0
    var page: ReferencePage?

    init(data: Data, caption: String? = nil, order: Int = 0) {
        self.data = data
        self.caption = caption
        self.order = order
    }
}

//
//  Trip.swift
//  Dipstick
//

import Foundation
import SwiftData

/// One recorded drive, summarized. Only totals are kept, never the route.
@Model
final class Trip {
    /// Stays the same on every phone, for iCloud sync and sharing. Optional
    /// so existing records get their own (see `SyncIDs.assign`); a default
    /// would give them all the same one.
    var syncID: String?
    /// Who added it, on a shared car ("Mom"); nil for your own.
    var addedBy: String?
    enum Status: String {
        /// Recorded but not yet confirmed as one of your cars.
        case unreviewed
        /// Belongs to `vehicle`.
        case assigned
        /// A ride, rental or someone else's car; ignored for MPG.
        case notMine
    }

    var startDate: Date = Date()
    var endDate: Date = Date()
    var cityMiles: Double = 0
    var highwayMiles: Double = 0
    /// Stored as text so CloudKit can sync it; use `status`.
    var statusRaw: String = Status.unreviewed.rawValue
    /// Name of the car audio connection (CarPlay/Bluetooth) seen during the
    /// trip, used to recognize which car it was.
    var connectionName: String?
    /// Stable ID of that connection (see `CarConnection.id`).
    var connectionID: String?
    var vehicle: Vehicle?

    init(
        startDate: Date,
        endDate: Date,
        cityMiles: Double,
        highwayMiles: Double,
        status: Status = .unreviewed,
        connectionName: String? = nil,
        connectionID: String? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.cityMiles = cityMiles
        self.highwayMiles = highwayMiles
        self.statusRaw = status.rawValue
        self.connectionName = connectionName
        self.connectionID = connectionID
    }

    var status: Status {
        get { Status(rawValue: statusRaw) ?? .unreviewed }
        set { statusRaw = newValue.rawValue }
    }

    var totalMiles: Double { cityMiles + highwayMiles }

    var highwayFraction: Double? {
        totalMiles > 0 ? highwayMiles / totalMiles : nil
    }
}

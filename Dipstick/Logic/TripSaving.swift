//
//  TripSaving.swift
//  Dipstick
//

import Foundation
import SwiftData

extension Trip {
    /// A trip that starts this soon after the same car's previous trip ended
    /// continues that trip instead (e.g. the head unit rebooted during a long
    /// red light, so the first part ended and a new one started on reconnect).
    static let continueWindow: TimeInterval = 600

    /// Saves a recorded drive: adds it to the same car's previous trip if that
    /// ended within `continueWindow`, otherwise creates a new trip.
    @MainActor
    @discardableResult
    static func save(
        start: Date,
        end: Date,
        split: TripClassifier.Split,
        vehicle: Vehicle?,
        connection: CarConnection?,
        in context: ModelContext
    ) -> Trip {
        if let previous = continuable(start: start, vehicle: vehicle, connection: connection, in: context) {
            previous.cityMiles += split.cityMiles
            previous.highwayMiles += split.highwayMiles
            previous.endDate = max(previous.endDate, end)
            try? context.save()
            return previous
        }
        let trip = Trip(
            startDate: start, endDate: end,
            cityMiles: split.cityMiles, highwayMiles: split.highwayMiles,
            status: vehicle == nil ? .unreviewed : .assigned,
            connectionName: connection?.name,
            connectionID: connection?.id
        )
        context.insert(trip)
        trip.vehicle = vehicle
        // Save now: a trip stopped in the background may be suspended before
        // SwiftData's autosave runs.
        try? context.save()
        return trip
    }

    /// The same car's most recent trip, if it ended within `continueWindow`
    /// before `start`. Without a known car, the same connection must match.
    @MainActor
    private static func continuable(start: Date, vehicle: Vehicle?, connection: CarConnection?,
                                    in context: ModelContext) -> Trip? {
        let earliest = start - continueWindow
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.endDate >= earliest },
            sortBy: [SortDescriptor(\.endDate, order: .reverse)]
        )
        descriptor.fetchLimit = 5
        let recent = (try? context.fetch(descriptor)) ?? []
        return recent.first { trip in
            guard trip.endDate <= start + 1 else { return false }
            if let vehicle {
                return trip.vehicle?.persistentModelID == vehicle.persistentModelID
            }
            guard let id = connection?.id else { return false }
            return trip.vehicle == nil && trip.connectionID == id
        }
    }
}

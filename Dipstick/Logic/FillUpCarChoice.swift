//
//  FillUpCarChoice.swift
//  Dipstick
//

import Foundation

extension Vehicle {
    /// The last time this car was used in the app: its latest drive,
    /// fill-up or service.
    var lastUsed: Date? {
        let trip = (trips ?? []).filter { $0.status == .assigned }.map(\.endDate).max()
        let fuel = (fuelEntries ?? []).map(\.date).max()
        let service = (maintenanceEntries ?? []).map(\.date).max()
        return [trip, fuel, service].compactMap { $0 }.max()
    }

    /// Cars to offer for a fill-up: the one connected now (CarPlay or
    /// Bluetooth) first, then the most recently used.
    static func orderedForFillUp(_ vehicles: [Vehicle], connected: Vehicle? = nil) -> [Vehicle] {
        vehicles.sorted { a, b in
            if a === connected { return b !== connected }
            if b === connected { return false }
            return (a.lastUsed ?? .distantPast, b.name) > (b.lastUsed ?? .distantPast, a.name)
        }
    }
}

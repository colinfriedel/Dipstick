//
//  CarDirectory.swift
//  Dipstick (app and Control Center extension)
//

import AppIntents
import Foundation

/// The cars' names and IDs, shared with the Control Center extension
/// through the app group (the extension can't open the app's database).
/// The app writes it whenever the cars change.
nonisolated enum CarDirectory {
    static let appGroup = "group.com.colinfriedel.Dipstick"
    private static let key = "cars"

    struct Car: Codable, Equatable, Hashable {
        var id: String
        var name: String
        /// MPG of the latest full tank, for the Lock Screen widget.
        var lastMPG: Double?
    }

    static func car(id: String?) -> Car? {
        guard let id else { return nil }
        return cars.first { $0.id == id }
    }

    /// Opens the app at the pump scanner, for one car or (nil) asking which:
    /// dipstick://fillup?car=ID.
    static func fillUpURL(carID: String?) -> URL {
        var components = URLComponents()
        components.scheme = "dipstick"
        components.host = "fillup"
        if let carID { components.queryItems = [URLQueryItem(name: "car", value: carID)] }
        return components.url!
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static var cars: [Car] {
        guard let data = defaults?.data(forKey: key),
              let cars = try? JSONDecoder().decode([Car].self, from: data) else { return [] }
        return cars
    }

    /// Saves the list; true if it changed.
    @discardableResult
    static func save(_ cars: [Car]) -> Bool {
        guard cars != self.cars, let data = try? JSONEncoder().encode(cars) else { return false }
        defaults?.set(data, forKey: key)
        return true
    }
}

/// A car to pick when setting up a Control Center button.
struct CarEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Car"
    static let defaultQuery = CarQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct CarQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CarEntity] {
        CarDirectory.cars.filter { identifiers.contains($0.id) }.map { CarEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [CarEntity] {
        CarDirectory.cars.map { CarEntity(id: $0.id, name: $0.name) }
    }
}

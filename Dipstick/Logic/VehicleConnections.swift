//
//  VehicleConnections.swift
//  Dipstick
//

import Foundation
import SwiftData

extension Vehicle {
    /// Every connection known to belong to this car (CarPlay, Bluetooth, …).
    var connections: [CarConnection] {
        var result: [CarConnection] = knownConnections
            .split(separator: "\n")
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                guard let id = parts.first, !id.isEmpty else { return nil }
                return CarConnection(name: parts.count > 1 ? parts[1] : id, id: id)
            }
        if let legacy = connectionID, !result.contains(where: { $0.id == legacy }) {
            result.insert(CarConnection(name: connectionName ?? legacy, id: legacy), at: 0)
        }
        return result
    }

    func knowsConnection(_ id: String?) -> Bool {
        guard let id else { return false }
        return connections.contains { $0.id == id }
    }

    /// Remembers a connection for this car (no-op if already known).
    func addConnection(_ connection: CarConnection) {
        guard !knowsConnection(connection.id) else { return }
        setConnections(connections + [connection])
    }

    func removeConnection(id: String) {
        setConnections(connections.filter { $0.id != id })
    }

    private func setConnections(_ list: [CarConnection]) {
        knownConnections = list
            .map { "\($0.id)\t\($0.name.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " "))" }
            .joined(separator: "\n")
        connectionID = nil
        connectionName = nil
    }

    /// The vehicle that knows `connection`, if any.
    static func matching(_ connection: CarConnection?, in context: ModelContext) -> Vehicle? {
        guard let id = connection?.id else { return nil }
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>())) ?? []
        return vehicles.first { $0.knowsConnection(id) }
    }
}

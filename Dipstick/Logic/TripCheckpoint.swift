//
//  TripCheckpoint.swift
//  Dipstick
//

import Foundation
import SwiftData

/// A snapshot of the trip being recorded, written about once a minute. If iOS
/// closes the app mid-drive (swiped away, or reclaimed for memory) the
/// in-memory trip would be lost; on the next launch the checkpoint is turned
/// into a saved trip instead. Stays on the device and is deleted once used.
struct TripCheckpoint: Codable {
    var startDate: Date
    var vehicleID: PersistentIdentifier?
    var connectionName: String?
    var connectionID: String?
    /// Last time the car was at driving speed; later samples are trimmed.
    var lastMoving: Date
    var samples: [TripClassifier.Sample]

    static let interval: TimeInterval = 60

    static var url: URL {
        URL.applicationSupportDirectory.appending(path: "trip-in-progress.json")
    }

    func write() {
        do {
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: Self.url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Best effort: losing a checkpoint only matters if the app is also killed.
        }
    }

    static func read() -> TripCheckpoint? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TripCheckpoint.self, from: data)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Turns a leftover checkpoint into a saved trip. Returns nil (and deletes
    /// the checkpoint) if it's too short to keep.
    @MainActor
    @discardableResult
    func recover(into context: ModelContext) -> Trip? {
        defer { Self.delete() }
        let kept = samples.filter { $0.timestamp <= lastMoving }
        let split = TripClassifier.classify(kept)
        guard split.totalMiles >= 0.1 else { return nil }

        let vehicle = vehicleID.flatMap { context.model(for: $0) as? Vehicle }
        let connection = connectionID.map { CarConnection(name: connectionName ?? $0, id: $0) }
        return Trip.save(
            start: startDate, end: kept.last?.timestamp ?? startDate, split: split,
            vehicle: vehicle, connection: connection, in: context
        )
    }
}

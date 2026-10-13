//
//  SpeedLog.swift
//  Dipstick
//

#if DEBUG
import Foundation
import CoreLocation

/// Debug-only: saves each recorded drive's speed trace (no coordinates) as a
/// CSV in the app's Documents folder, so classifier thresholds can be tuned
/// against real drives. Not compiled into Release builds.
enum SpeedLog {
    static let header = "seconds,speed_mph,step_miles,accuracy_m"

    /// One row per sample: seconds since the first sample, reported speed
    /// (-1 if unknown), distance from the previous sample, GPS accuracy.
    static func csv(for samples: [TripClassifier.Sample]) -> String {
        guard let first = samples.first else { return header + "\n" }
        var lines = [header]
        var previous: TripClassifier.Sample?
        for sample in samples {
            let seconds = sample.timestamp.timeIntervalSince(first.timestamp)
            let speed = sample.speed >= 0 ? sample.speed * TripClassifier.mphPerMetersPerSecond : -1
            let stepMiles = previous.map {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                    .distance(from: CLLocation(latitude: sample.latitude, longitude: sample.longitude))
                    / TripClassifier.metersPerMile
            } ?? 0
            lines.append(String(format: "%.1f,%.2f,%.5f,%.1f", seconds, speed, stepMiles, sample.horizontalAccuracy))
            previous = sample
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// File for a trip, named by its start time so it can be found from the trip.
    static func url(forTripStartingAt start: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return URL.documentsDirectory.appending(path: "speed-\(formatter.string(from: start)).csv")
    }

    static func save(_ samples: [TripClassifier.Sample], tripStart: Date) {
        try? Data(csv(for: samples).utf8).write(to: url(forTripStartingAt: tripStart), options: .atomic)
    }

    static func existingURL(forTripStartingAt start: Date) -> URL? {
        let url = url(forTripStartingAt: start)
        return FileManager.default.fileExists(atPath: url.path()) ? url : nil
    }
}
#endif

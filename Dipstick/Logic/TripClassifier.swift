//
//  TripClassifier.swift
//  Dipstick
//

import Foundation
import CoreLocation

/// Splits a drive's miles into city and highway from GPS samples.
///
/// The drive is cut into stretches of about half a mile. A stretch is highway
/// when it averages at least `highwayAverageMPH` and never drops below
/// `highwayMinimumMPH` (so a freeway traffic jam counts as city driving, which
/// is how the engine experiences it). Everything else is city.
enum TripClassifier {
    // Tunable thresholds.
    static let segmentMiles = 0.5
    static let highwayAverageMPH = 45.0
    static let highwayMinimumMPH = 25.0
    /// Samples less accurate than this are ignored.
    static let maxHorizontalAccuracyMeters = 50.0
    /// Gaps longer than this (GPS dropout, tunnel) aren't bridged with a
    /// straight line; the distance across them is skipped.
    static let maxGapSeconds = 30.0
    /// Below this the car is standing still; GPS jitter isn't distance. The
    /// time still counts, so a red light still makes a stretch city driving.
    static let stoppedMPH = 1.0

    struct Sample: Equatable {
        let timestamp: Date
        let latitude: Double
        let longitude: Double
        /// Meters per second; negative if unknown.
        let speed: Double
        let horizontalAccuracy: Double
    }

    struct Split: Equatable {
        var cityMiles: Double = 0
        var highwayMiles: Double = 0
        var totalMiles: Double { cityMiles + highwayMiles }
    }

    static let metersPerMile = 1_609.344
    static let mphPerMetersPerSecond = 2.236_936

    static func classify(_ samples: [Sample]) -> Split {
        let usable = samples
            .filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= maxHorizontalAccuracyMeters }
            .sorted { $0.timestamp < $1.timestamp }

        var split = Split()
        var stretchMiles = 0.0
        var stretchSeconds = 0.0
        var stretchMinMPH = Double.infinity

        func closeStretch() {
            guard stretchMiles > 0 else { return }
            let averageMPH = stretchSeconds > 0 ? stretchMiles / (stretchSeconds / 3_600) : 0
            if averageMPH >= highwayAverageMPH && stretchMinMPH >= highwayMinimumMPH {
                split.highwayMiles += stretchMiles
            } else {
                split.cityMiles += stretchMiles
            }
            stretchMiles = 0
            stretchSeconds = 0
            stretchMinMPH = .infinity
        }

        for (previous, current) in zip(usable, usable.dropFirst()) {
            let seconds = current.timestamp.timeIntervalSince(previous.timestamp)
            guard seconds > 0, seconds <= maxGapSeconds else {
                // A long gap ends the current stretch rather than guessing.
                closeStretch()
                continue
            }
            let meters = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                .distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude))
            let miles = meters / metersPerMile

            // Prefer the GPS-reported speed; fall back to distance over time.
            let reported = current.speed >= 0 ? current.speed * mphPerMetersPerSecond : nil
            let mph = reported ?? miles / (seconds / 3_600)

            stretchMiles += mph < stoppedMPH ? 0 : miles
            stretchSeconds += seconds
            stretchMinMPH = min(stretchMinMPH, mph)
            if stretchMiles >= segmentMiles {
                closeStretch()
            }
        }
        closeStretch()
        return split
    }
}

extension TripClassifier.Sample {
    init(_ location: CLLocation) {
        self.init(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speed: location.speed,
            horizontalAccuracy: location.horizontalAccuracy
        )
    }
}

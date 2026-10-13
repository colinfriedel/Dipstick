//
//  TripClassifierTests.swift
//  DipstickTests
//

import Foundation
import Testing
@testable import Dipstick

@MainActor
struct TripClassifierTests {
    private typealias Sample = TripClassifier.Sample

    /// Builds a drive heading north, one sample per second, from a list of
    /// (seconds, mph) legs.
    private func drive(_ legs: [(seconds: Int, mph: Double)], accuracy: Double = 5) -> [Sample] {
        let metersPerDegreeLat = 111_320.0
        var samples: [Sample] = []
        var time = Date(timeIntervalSince1970: 1_790_000_000)
        var latitude = 37.0
        samples.append(Sample(timestamp: time, latitude: latitude, longitude: -122, speed: 0, horizontalAccuracy: accuracy))
        for leg in legs {
            let metersPerSecond = leg.mph / TripClassifier.mphPerMetersPerSecond
            for _ in 0..<leg.seconds {
                time += 1
                latitude += metersPerSecond / metersPerDegreeLat
                samples.append(Sample(timestamp: time, latitude: latitude, longitude: -122,
                                      speed: metersPerSecond, horizontalAccuracy: accuracy))
            }
        }
        return samples
    }

    private func isClose(_ a: Double, _ b: Double, tolerance: Double = 0.05) -> Bool {
        abs(a - b) <= tolerance
    }

    @Test func steadyFreewayIsHighway() {
        let split = TripClassifier.classify(drive([(600, 65)]))  // 10 min at 65 = 10.83 mi
        #expect(isClose(split.totalMiles, 10.83))
        #expect(split.cityMiles < 0.6)  // at most the final partial stretch
        #expect(split.highwayMiles / split.totalMiles > 0.95)
    }

    @Test func surfaceStreetsAreCity() {
        let split = TripClassifier.classify(drive([(900, 30)]))  // 7.5 mi at 30
        #expect(isClose(split.totalMiles, 7.5))
        #expect(split.highwayMiles == 0)
    }

    @Test func stopAndGoIsCity() {
        // 30 s at 40 mph, 20 s stopped, repeated.
        let legs = Array(repeating: [(30, 40.0), (20, 0.0)], count: 20).flatMap { $0 }
        let split = TripClassifier.classify(drive(legs))
        #expect(split.totalMiles > 6)
        #expect(split.highwayMiles == 0)
    }

    @Test func freewayTrafficJamCountsAsCity() {
        // Fast, then a 1.5-mile crawl at 15 mph, then fast again.
        let split = TripClassifier.classify(drive([(300, 65), (360, 15), (300, 65)]))
        #expect(isClose(split.totalMiles, 5.42 + 1.5 + 5.42, tolerance: 0.1))
        #expect(split.cityMiles >= 1.5 - 0.05)
        #expect(split.highwayMiles >= 9.5)
    }

    @Test func mixedDriveSplitsByPortion() {
        // 2.5 mi of 30 mph streets, then 10 mi of 60 mph freeway.
        let split = TripClassifier.classify(drive([(300, 30), (600, 60)]))
        #expect(isClose(split.cityMiles, 2.5, tolerance: 0.55))
        #expect(isClose(split.highwayMiles, 10, tolerance: 0.55))
    }

    @Test func inaccurateSamplesAreIgnored() {
        let good = drive([(300, 60)])
        let noisy = good.enumerated().map { index, sample in
            // Every 10th sample is a wild 500 m-off reading with poor accuracy.
            index % 10 == 5
                ? Sample(timestamp: sample.timestamp, latitude: sample.latitude + 0.005, longitude: sample.longitude,
                         speed: sample.speed, horizontalAccuracy: 200)
                : sample
        }
        #expect(isClose(TripClassifier.classify(noisy).totalMiles, TripClassifier.classify(good).totalMiles, tolerance: 0.01))
    }

    @Test func longGpsGapIsNotBridged() {
        var samples = drive([(120, 60)])
        // Jump 5 miles north two minutes later (tunnel or GPS loss).
        let last = samples.last!
        samples.append(Sample(timestamp: last.timestamp + 120, latitude: last.latitude + 5 * 1_609.344 / 111_320,
                              longitude: last.longitude, speed: 26.8, horizontalAccuracy: 5))
        let split = TripClassifier.classify(samples)
        #expect(isClose(split.totalMiles, 2.0))
    }

    @Test func emptyOrSingleSampleHasNoMiles() {
        #expect(TripClassifier.classify([]).totalMiles == 0)
        #expect(TripClassifier.classify(Array(drive([(1, 30)]).prefix(1))).totalMiles == 0)
    }
}

#if DEBUG
@MainActor
struct SpeedLogTests {
    @Test func logsSpeedsAndStepDistancesWithoutCoordinates() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let samples = (0..<3).map { i in
            TripClassifier.Sample(timestamp: start + Double(i), latitude: 37.123456 + Double(i) * 0.0003,
                                  longitude: -122.654321, speed: 26.8224, horizontalAccuracy: 5)
        }
        let lines = SpeedLog.csv(for: samples).split(separator: "\n").map(String.init)
        #expect(lines.first == SpeedLog.header)
        #expect(lines.count == 4)
        #expect(lines[1].hasPrefix("0.0,60.00,0.00000,"))
        #expect(lines[2].hasPrefix("1.0,60.00,0.020"))  // 0.0003° latitude ≈ 33 m ≈ 0.0207 mi
        #expect(!SpeedLog.csv(for: samples).contains("37.12"))
        #expect(!SpeedLog.csv(for: samples).contains("122.65"))
    }
}
#endif

@MainActor
struct CarConnectionTests {
    @Test func stableIDIsTheHardwareAddressPrefix() {
        #expect(CarConnection.stableID(fromUID: "1C:50:1E:B4:BC:F1-Audio-AudioMain-1592965438827625") == "1C:50:1E:B4:BC:F1")
        #expect(CarConnection.stableID(fromUID: "00:00:05:04:37:20-Audio-AudioMain-1593073765289416") == "00:00:05:04:37:20")
        #expect(CarConnection.stableID(fromUID: "NoDashes") == "NoDashes")
    }
}

@MainActor
struct AutoStopTests {
    private typealias Rule = TripRecorder.AutoStop
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func headUnitRebootWhileDrivingDoesNotStop() {
        // Connection gone and Stop Trip ran, but you were moving 10 s ago.
        #expect(!Rule.shouldStop(now: now, lastMoving: now - 10, connectionPresent: false, stopRequested: true))
    }

    @Test func redLightWhileDisconnectedDoesNotStop() {
        #expect(!Rule.shouldStop(now: now, lastMoving: now - 90, connectionPresent: false, stopRequested: true))
    }

    @Test func parkedAndDisconnectedStops() {
        #expect(Rule.shouldStop(now: now, lastMoving: now - 180, connectionPresent: false, stopRequested: false))
    }

    @Test func parkedButStillConnectedKeepsRecording() {
        // Sitting in the driveway plugged in: wait for the unplug.
        #expect(!Rule.shouldStop(now: now, lastMoving: now - 3_600, connectionPresent: true, stopRequested: false))
    }

    @Test func stopRequestWhileConnectedEndsOnceParked() {
        #expect(Rule.shouldStop(now: now, lastMoving: now - 200, connectionPresent: true, stopRequested: true))
    }
}

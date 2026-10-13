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

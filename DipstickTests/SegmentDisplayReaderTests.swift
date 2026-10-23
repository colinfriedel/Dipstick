//
//  SegmentDisplayReaderTests.swift
//  DipstickTests
//
//  Real pump photos stay in private/pump-photos (tools/scan_segments.swift);
//  these draw synthetic segment displays so the reader is tested in the repo.
//

import CoreGraphics
import Foundation
import Testing
@testable import Dipstick

@MainActor
struct SegmentDisplayReaderTests {
    struct Style {
        var slant = 0.12            // digits lean right, as on most pumps
        var lightSegments = false   // lit segments on a dark display
        var frame = true            // the display's dark frame around it
        var glare = false           // a bright wash over part of the display
    }

    /// Draws "TOTAL" over "GALLONS" as seven-segment digits (with decimal
    /// points), like a pump's main display.
    func display(_ total: String, _ gallons: String, style: Style = .init()) -> CGImage {
        let width = 900, height = 520
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let background: CGFloat = style.lightSegments ? 0.12 : 0.78
        let ink: CGFloat = style.lightSegments ? 0.9 : 0.12
        context.setFillColor(gray: style.frame ? 0.25 : background, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: background, alpha: 1)
        context.fill(CGRect(x: 40, y: 40, width: width - 80, height: height - 80))

        // Core Graphics' origin is at the bottom left.
        drawRow(total, in: context, right: 820, baseline: 300, height: 150, ink: ink, slant: style.slant)
        drawRow(gallons, in: context, right: 820, baseline: 80, height: 110, ink: ink, slant: style.slant)

        if style.glare {
            let colors = [CGColor(gray: 1, alpha: 0.55), CGColor(gray: 1, alpha: 0)] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 1])!
            context.drawRadialGradient(gradient, startCenter: CGPoint(x: 300, y: 380), startRadius: 0,
                                       endCenter: CGPoint(x: 300, y: 380), endRadius: 320, options: [])
        }
        return context.makeImage()!
    }

    static let segments: [Character: String] = [
        "0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg",
        "5": "acdfg", "6": "acdefg", "7": "abc", "8": "abcdefg", "9": "abcdfg",
    ]

    func drawRow(_ text: String, in context: CGContext, right: CGFloat, baseline: CGFloat,
                 height: CGFloat, ink: CGFloat, slant: CGFloat) {
        let w = height * 0.55, pitch = height * 0.72, t = height * 0.1
        context.setFillColor(gray: ink, alpha: 1)
        let digits = text.filter(\.isNumber)
        var x = right - w
        var pointBefore = false
        for character in text.reversed() {
            if character == "." { pointBefore = true; continue }
            let shear = CGAffineTransform(a: 1, b: 0, c: slant, d: 1, tx: -slant * baseline, ty: 0)
            func bar(_ r: CGRect) { context.addPath(CGPath(rect: r, transform: [shear])) }
            let half = height / 2, gap = t * 0.25
            for segment in Self.segments[character] ?? "" {
                switch segment {
                case "a": bar(CGRect(x: x + t, y: baseline + height - t, width: w - 2 * t, height: t))
                case "g": bar(CGRect(x: x + t, y: baseline + half - t / 2, width: w - 2 * t, height: t))
                case "d": bar(CGRect(x: x + t, y: baseline, width: w - 2 * t, height: t))
                case "f": bar(CGRect(x: x, y: baseline + half + gap, width: t, height: half - t - gap))
                case "b": bar(CGRect(x: x + w - t, y: baseline + half + gap, width: t, height: half - t - gap))
                case "e": bar(CGRect(x: x, y: baseline + t, width: t, height: half - t - gap))
                case "c": bar(CGRect(x: x + w - t, y: baseline + t, width: t, height: half - t - gap))
                default: break
                }
            }
            context.fillPath()
            if pointBefore {
                // The point sits in the gap to this digit's right.
                let dot = CGRect(x: x + w + (pitch - w) / 2 - t / 2, y: baseline, width: t, height: t)
                context.fill(dot.applying(CGAffineTransform(a: 1, b: 0, c: slant, d: 1, tx: -slant * baseline, ty: 0)))
                pointBefore = false
            }
            x -= pitch
        }
        _ = digits
    }

    func read(_ total: String, _ gallons: String, style: Style = .init()) -> PumpReadingParser.Reading? {
        SegmentDisplayReader.read(display(total, gallons, style: style)).reading
    }

    @Test(arguments: [
        ("16.59", "6.536"), ("42.82", "10.872"), ("10.21", "3.003"), ("38.83", "9.958"),
        ("8.61", "2.778"), ("17.81", "5.019"), ("175.00", "25.739"), ("21.36", "7.368"),
        ("10.09", "3.060"), ("73.87", "10.555"), ("60.06", "9.768"),
    ])
    func readsPumpDisplays(total: String, gallons: String) {
        let reading = read(total, gallons)
        #expect(reading?.total == Double(total), "\(total) / \(gallons)")
        #expect(reading?.gallons == Double(gallons), "\(total) / \(gallons)")
    }

    @Test func readsUprightDigitsAndLitSegments() {
        #expect(read("42.82", "10.872", style: .init(slant: 0))?.total == 42.82)
        #expect(read("42.82", "10.872", style: .init(lightSegments: true))?.total == 42.82)
    }

    @Test func readsWithoutAFrameAndThroughGlare() {
        #expect(read("38.83", "9.958", style: .init(frame: false))?.gallons == 9.958)
        #expect(read("38.83", "9.958", style: .init(glare: true))?.total == 38.83)
    }

    @Test func priceFitsANineTenthsPrice() {
        let reading = read("73.87", "10.555")
        #expect(reading?.pricePerGallon == 6.999)
        #expect(reading?.confidence == .priceFits)
    }

    @Test func digitsCutOffAtTheEdgeGiveNoReading() {
        // Filling the frame too tightly: the crop cuts into the last digits.
        let image = display("42.82", "10.872")
        let cropped = image.cropping(to: CGRect(x: 0, y: 0, width: image.width - 120, height: image.height))!
        #expect(SegmentDisplayReader.read(cropped).reading == nil)
        let leftCut = image.cropping(to: CGRect(x: 470, y: 0, width: image.width - 470, height: image.height))!
        #expect(SegmentDisplayReader.read(leftCut).reading == nil)
    }

    @Test func blankImageHasNoReading() {
        let context = CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(SegmentDisplayReader.read(context.makeImage()!).reading == nil)
    }

    @Test func eachDigitMatchesItsOwnPattern() {
        for (digit, lit) in Self.segments {
            let coverage = Dictionary(uniqueKeysWithValues: "abcdefg".map { ($0, lit.contains($0) ? 1.0 : 0.0) })
            #expect(SegmentDisplayReader.rank(coverage).first?.character == digit)
        }
    }
}

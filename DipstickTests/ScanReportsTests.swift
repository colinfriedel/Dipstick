//
//  ScanReportsTests.swift
//  DipstickTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Dipstick

@MainActor
struct ScanReportsTests {
    private func image() -> CGImage {
        let context = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 0.7, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        return context.makeImage()!
    }

    @Test func savesPhotoAndAppendsAnswersInTheToolsFormat() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let misread = PumpReadingParser.Reading(gallons: 10.555, total: 73.81, pricePerGallon: 6.993, confidence: .priceInferred)
        let evidence = ScanEvidence(image: image(), orientation: .right,
                                    crop: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25), reading: misread)

        #expect(ScanReports.save(evidence, total: 73.87, gallons: 10.555, in: folder))
        #expect(ScanReports.save(ScanEvidence(image: image(), orientation: .up, crop: .init(x: 0, y: 0, width: 1, height: 1),
                                              reading: nil), total: 42.82, gallons: 10.872, in: folder))

        let csv = try String(contentsOf: folder.appendingPathComponent("answers.csv"), encoding: .utf8)
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        #expect(lines[0] == ScanReports.header)
        let first = lines[1].split(separator: ",").map(String.init)
        #expect(first[1] == "73.87" && first[2] == "10.555" && first[3] == "6.999")
        #expect(first[4...7] == ["0.100", "0.200", "0.500", "0.250"])
        #expect(first[8] == "10.555 gal $73.81")
        #expect(lines[2].hasSuffix(",nothing"))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(first[0]).path))
    }
}

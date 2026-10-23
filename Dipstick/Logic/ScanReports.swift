//
//  ScanReports.swift
//  Dipstick
//

import Foundation
import CoreGraphics
import ImageIO

/// A pump scan's photo and what the reader made of it, kept until the
/// fill-up is saved in case it's reported as a misread.
nonisolated struct ScanEvidence: @unchecked Sendable {
    let image: CGImage
    let orientation: CGImagePropertyOrientation
    /// Where the reader looked, as fractions of the oriented photo from the
    /// top left.
    let crop: CGRect
    /// What it read; nil if it couldn't read anything.
    let reading: PumpReadingParser.Reading?
}

/// Misread scans the user reported, saved for tuning the reader: photos plus
/// an answers.csv (the format tools/scan_segments.swift reads) in
/// Documents/Pump scans, which shows in Files › On My iPhone › Dipstick.
/// The correct numbers are what the user saved on the form.
nonisolated enum ScanReports {
    static var folder: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Pump scans", isDirectory: true)
    }

    static let header = "file,total,gallons,price,x,y,w,h,read"

    /// Saves the photo and appends its answer. Returns false if it couldn't.
    @discardableResult
    static func save(_ evidence: ScanEvidence, total: Double, gallons: Double, in folder: URL? = folder) -> Bool {
        guard let folder else { return false }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        let name = "scan-\(stamp).jpg"
        let url = folder.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, evidence.image, [
            kCGImagePropertyOrientation: evidence.orientation.rawValue,
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return false }

        let price = gallons > 0 ? total / gallons : 0
        let read = evidence.reading.map { String(format: "%.3f gal $%.2f", $0.gallons, $0.total) } ?? "nothing"
        let c = evidence.crop
        let row = String(format: "%@,%.2f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%@", locale: Locale(identifier: "en_US_POSIX"),
                         name, total, gallons, price, c.minX, c.minY, c.width, c.height, read)
        return append(row, to: folder.appendingPathComponent("answers.csv"))
    }

    private static func append(_ row: String, to csv: URL) -> Bool {
        if !FileManager.default.fileExists(atPath: csv.path) {
            guard (try? (header + "\n").write(to: csv, atomically: true, encoding: .utf8)) != nil else { return false }
        }
        guard let handle = try? FileHandle(forWritingTo: csv) else { return false }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(Data((row + "\n").utf8))
        return true
    }
}

//
//  PumpPhotoReader.swift
//  Dipstick
//

import Foundation
import Vision
import CoreImage

/// Reads a still photo of a pump display harder than the live scanner can:
/// text recognition runs on the photo as taken and on a few adjusted copies
/// (high-contrast grayscale, darkened for sun glare), and the best reading
/// wins. No UIKit, so tools/scan_pump_photo.swift can reuse it on a Mac.
nonisolated enum PumpPhotoReader {
    struct Variant {
        let name: String
        let lines: [String]
        let reading: PumpReadingParser.Reading?
    }

    struct Result {
        let reading: PumpReadingParser.Reading?
        /// What each version of the photo read, for tuning.
        let variants: [Variant]
    }

    private static let context = CIContext()

    static func read(_ image: CGImage, orientation: CGImagePropertyOrientation = .up,
                     expectedPrice: Double? = nil) -> Result {
        let source = CIImage(cgImage: image).oriented(orientation)
        let versions: [(String, CIImage)] = [
            ("original", source),
            ("contrast", source.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0, kCIInputContrastKey: 1.8,
            ])),
            ("darker", source.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -1.2])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0, kCIInputContrastKey: 1.5,
                ])),
            ("brighter", source.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: 1.0])
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0, kCIInputContrastKey: 1.4,
                ])),
        ]

        let variants = versions.map { name, version -> Variant in
            let lines = context.createCGImage(version, from: version.extent).map(recognizedLines) ?? []
            return Variant(name: name, lines: lines,
                           reading: PumpReadingParser.parse(lines, expectedPrice: expectedPrice))
        }
        return Result(reading: best(of: variants.compactMap(\.reading)), variants: variants)
    }

    /// The most confident reading; among equals, the one most versions agree on.
    static func best(of readings: [PumpReadingParser.Reading]) -> PumpReadingParser.Reading? {
        func votes(_ r: PumpReadingParser.Reading) -> Int { readings.filter { $0 == r }.count }
        return readings.max { a, b in (a.confidence, votes(a)) < (b.confidence, votes(b)) }
    }

    static func recognizedLines(in image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false  // numbers, not words
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}

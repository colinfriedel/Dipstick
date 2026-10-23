//
//  PumpPhotoReader.swift
//  Dipstick
//

import Foundation
import Vision
import CoreImage

/// Reads a still photo of a pump display harder than the live scanner can.
///
/// Text recognition is unreliable on segment digits: one photo of "$73.87"
/// reads as 1387, 13.8, 738, 73.8, 7387 or 73.87 depending on brightness. So
/// the photo is read at several brightness and contrast levels, both whole
/// and cropped to the scan frame, and the reading most versions agree on wins.
/// No UIKit, so tools/scan_pump_photo.swift can reuse it on a Mac.
nonisolated enum PumpPhotoReader {
    struct Adjustment {
        let name: String
        let exposure: Double
        let saturation: Double
        let contrast: Double
    }

    /// Tuned on private/pump-photos: brighter grayscale versions recover
    /// segments that glare and the display's tint wash out.
    static let adjustments = [
        Adjustment(name: "original", exposure: 0, saturation: 1, contrast: 1),
        Adjustment(name: "gray", exposure: 0, saturation: 0, contrast: 1.4),
        Adjustment(name: "darker", exposure: -1.2, saturation: 0, contrast: 1.5),
        Adjustment(name: "ev+0.6", exposure: 0.6, saturation: 1, contrast: 1),
        Adjustment(name: "ev+1", exposure: 1.0, saturation: 1, contrast: 1),
        Adjustment(name: "ev+1 gray", exposure: 1.0, saturation: 0, contrast: 1.4),
        Adjustment(name: "ev+1.8", exposure: 1.8, saturation: 1, contrast: 1),
        Adjustment(name: "ev+1.8 gray", exposure: 1.8, saturation: 0, contrast: 1.8),
        Adjustment(name: "ev+2.4 gray", exposure: 2.4, saturation: 0, contrast: 1),
    ]

    struct Variant {
        let name: String
        let lines: [String]
        let reading: PumpReadingParser.Reading?
    }

    struct Result {
        let reading: PumpReadingParser.Reading?
        /// How many versions of the photo gave `reading`.
        let votes: Int
        /// What each version read, for tuning.
        let variants: [Variant]
        var readings: [PumpReadingParser.Reading] { variants.compactMap(\.reading) }
    }

    static let context = CIContext()

    /// - Parameter crop: also read this part on its own, as fractions of the
    ///   oriented photo with the origin at the top left (like a view).
    static func read(_ image: CGImage, orientation: CGImagePropertyOrientation = .up,
                     crop: CGRect? = nil, expectedPrice: Double? = nil) -> Result {
        let whole = CIImage(cgImage: image).oriented(orientation)
        var sources = [("", whole)]
        if let crop, let cropped = cropped(whole, to: crop) {
            sources.append(("crop ", cropped))
        }

        let variants = sources.flatMap { prefix, source in
            adjustments.map { read(source, adjustment: $0, prefix: prefix, expectedPrice: expectedPrice) }
        }
        let readings = variants.compactMap(\.reading)
        let best = best(of: readings)
        return Result(reading: best, votes: readings.filter { $0 == best }.count, variants: variants)
    }

    /// Part of an image, given as fractions with the origin at the top left.
    static func cropped(_ image: CIImage, to crop: CGRect) -> CIImage? {
        let e = image.extent
        // Core Image's origin is at the bottom left.
        let rect = CGRect(x: e.minX + crop.minX * e.width,
                          y: e.minY + (1 - crop.maxY) * e.height,
                          width: crop.width * e.width, height: crop.height * e.height)
            .intersection(e)
        return rect.isEmpty ? nil : image.cropped(to: rect)
    }

    static func adjusted(_ image: CIImage, _ adjustment: Adjustment) -> CIImage {
        var version = image
        if adjustment.exposure != 0 {
            version = version.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: adjustment.exposure])
        }
        if adjustment.saturation != 1 || adjustment.contrast != 1 {
            version = version.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: adjustment.saturation, kCIInputContrastKey: adjustment.contrast,
            ])
        }
        return version
    }

    private static func read(_ source: CIImage, adjustment: Adjustment, prefix: String,
                             expectedPrice: Double?) -> Variant {
        let version = adjusted(source, adjustment)
        let lines = context.createCGImage(version, from: version.extent).map(recognizedLines) ?? []
        return Variant(name: prefix + adjustment.name, lines: lines,
                       reading: PumpReadingParser.parse(lines, expectedPrice: expectedPrice))
    }

    /// The reading most versions agree on; a checked one (displayed price
    /// agrees) beats any number of inferred ones.
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

    /// Where a rect on screen falls in the photo, as fractions of the photo,
    /// when the camera preview shows the photo aspect-filled in `viewSize`.
    /// Grown by `margin` (a fraction of its size) on each side, since the
    /// preview and the photo may not line up exactly.
    static func crop(for rect: CGRect, in viewSize: CGSize, photoSize: CGSize, margin: Double = 0.2) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0, photoSize.width > 0, photoSize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let scale = max(viewSize.width / photoSize.width, viewSize.height / photoSize.height)
        let shown = CGSize(width: photoSize.width * scale, height: photoSize.height * scale)
        let offset = CGPoint(x: (viewSize.width - shown.width) / 2, y: (viewSize.height - shown.height) / 2)
        let grown = rect.insetBy(dx: -rect.width * margin, dy: -rect.height * margin)
        let fraction = CGRect(x: (grown.minX - offset.x) / shown.width,
                              y: (grown.minY - offset.y) / shown.height,
                              width: grown.width / shown.width,
                              height: grown.height / shown.height)
        return fraction.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}

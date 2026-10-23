// Runs the app's PumpPhotoReader (Apple's on-device text recognition on the
// photo and a few adjusted copies, then PumpReadingParser) on pump display
// photos, to check scanning accuracy on real pumps without the phone.
//
//   swiftc -O -parse-as-library tools/scan_pump_photo.swift Dipstick/Logic/PumpPhotoReader.swift \
//       Dipstick/Logic/PumpReadingParser.swift -o /tmp/scan_pump_photo
//   /tmp/scan_pump_photo [--price 6.10] [--crop x,y,w,h] private/pump-photos/*.jpg
//
// --crop reads part of the photo, as fractions from the top left
// (e.g. 0.28,0.33,0.5,0.2 for the display).

import Foundation
import ImageIO

func describe(_ reading: PumpReadingParser.Reading?) -> String {
    guard let reading else { return "no reading" }
    return String(format: "%.3f gal, $%.2f, $%.3f/gal (%@)",
                  reading.gallons, reading.total, reading.pricePerGallon,
                  reading.confidence == .checked ? "checked"
                    : reading.confidence == .priceFits ? "x.xx9 price fits"
                    : reading.confidence == .priceFitsCorrected ? "digit corrected to fit x.xx9" : "price inferred")
}

@main
struct ScanPumpPhoto {
    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        var expectedPrice: Double?
        if let index = arguments.firstIndex(of: "--price"), index + 1 < arguments.count {
            expectedPrice = Double(arguments[index + 1])
            arguments.removeSubrange(index...index + 1)
        }
        var crop: CGRect?
        if let index = arguments.firstIndex(of: "--crop"), index + 1 < arguments.count {
            let parts = arguments[index + 1].split(separator: ",").compactMap { Double($0) }
            if parts.count == 4 { crop = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]) }
            arguments.removeSubrange(index...index + 1)
        }
        if arguments.isEmpty {
            print("usage: scan_pump_photo [--price 6.10] [--crop x,y,w,h] <image> [image...]")
            exit(1)
        }
        for path in arguments {
            let url = URL(fileURLWithPath: path)
            print("== \(url.lastPathComponent)")
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                print("   couldn't open")
                continue
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32)
                .flatMap(CGImagePropertyOrientation.init) ?? .up

            let result = PumpPhotoReader.read(image, orientation: orientation, crop: crop, expectedPrice: expectedPrice)
            for variant in result.variants {
                let numeric = variant.lines.filter { $0.contains(where: \.isNumber) }
                print("   \(variant.name): \(numeric.joined(separator: " | "))")
                print("      → \(describe(variant.reading))")
            }
            print("   BEST → \(describe(result.reading)) [\(result.votes) of \(result.variants.count) versions]")
        }
    }
}

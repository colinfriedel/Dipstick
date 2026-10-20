// Runs the app's PumpPhotoReader (Apple's on-device text recognition on the
// photo and a few adjusted copies, then PumpReadingParser) on pump display
// photos, to check scanning accuracy on real pumps without the phone.
//
//   swiftc -O -parse-as-library tools/scan_pump_photo.swift Dipstick/Logic/PumpPhotoReader.swift \
//       Dipstick/Logic/PumpReadingParser.swift -o /tmp/scan_pump_photo
//   /tmp/scan_pump_photo [--price 6.10] private/pump-photos/*.jpg

import Foundation
import ImageIO

func describe(_ reading: PumpReadingParser.Reading?) -> String {
    guard let reading else { return "no reading" }
    return String(format: "%.3f gal, $%.2f, $%.3f/gal (%@)",
                  reading.gallons, reading.total, reading.pricePerGallon,
                  reading.confidence == .checked ? "checked" : "price inferred")
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
        if arguments.isEmpty {
            print("usage: scan_pump_photo [--price 6.10] <image> [image...]")
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

            let result = PumpPhotoReader.read(image, orientation: orientation, expectedPrice: expectedPrice)
            for variant in result.variants {
                let numeric = variant.lines.filter { $0.contains(where: \.isNumber) }
                print("   \(variant.name): \(numeric.joined(separator: " | "))")
                print("      → \(describe(variant.reading))")
            }
            print("   BEST → \(describe(result.reading))")
        }
    }
}

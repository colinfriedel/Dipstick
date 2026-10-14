// Runs Apple's on-device text recognition on pump display photos and feeds the
// text through the app's PumpReadingParser, to check scanning accuracy on real
// pumps without the phone.
//
//   swiftc -O -parse-as-library tools/scan_pump_photo.swift Dipstick/Logic/PumpReadingParser.swift -o /tmp/scan_pump_photo
//   /tmp/scan_pump_photo private/pump-photos/*.jpg

import Foundation
import Vision
import CoreImage

func recognizedLines(in url: URL) throws -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false  // numbers, not words
    try VNImageRequestHandler(url: url).perform([request])
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
}

@main
struct ScanPumpPhoto {
    static func main() {
        let paths = CommandLine.arguments.dropFirst()
        if paths.isEmpty {
            print("usage: scan_pump_photo <image> [image...]")
            exit(1)
        }
        for path in paths {
            let url = URL(fileURLWithPath: path)
            print("== \(url.lastPathComponent)")
            do {
                let lines = try recognizedLines(in: url)
                print("   text: \(lines.joined(separator: " | "))")
                if let reading = PumpReadingParser.parse(lines) {
                    print(String(format: "   → %.3f gal, $%.2f, $%.3f/gal (%@)",
                                 reading.gallons, reading.total, reading.pricePerGallon,
                                 reading.confidence == .checked ? "checked" : "price inferred"))
                } else {
                    print("   → no reading")
                }
            } catch {
                print("   error: \(error)")
            }
        }
    }
}

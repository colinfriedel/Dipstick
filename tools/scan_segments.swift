// Runs the app's SegmentDisplayReader on pump photos and checks it against an
// answer key, to tune the reader without the phone.
//
//   swiftc -O -parse-as-library tools/scan_segments.swift Dipstick/Logic/SegmentDisplayReader.swift \
//       Dipstick/Logic/PumpPhotoReader.swift Dipstick/Logic/PumpReadingParser.swift -o /tmp/scan_segments
//   /tmp/scan_segments [--verbose] [--dump /tmp/masks] private/pump-photos/answers.csv
//
// answers.csv: file,total,gallons,price[,x,y,w,h] (files relative to the CSV's
// folder). x,y,w,h is roughly where the scan frame would be, as fractions from
// the top left; --whole ignores it and reads the whole photo.

import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

@main
struct ScanSegments {
    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        let verbose = arguments.contains("--verbose")
        let whole = arguments.contains("--whole")
        arguments.removeAll { $0 == "--verbose" || $0 == "--whole" }
        var dump: URL?
        if let i = arguments.firstIndex(of: "--dump"), i + 1 < arguments.count {
            dump = URL(fileURLWithPath: arguments[i + 1])
            arguments.removeSubrange(i...i + 1)
        }
        guard let csvPath = arguments.first, let csv = try? String(contentsOfFile: csvPath, encoding: .utf8) else {
            print("usage: scan_segments [--verbose] [--dump dir] answers.csv")
            exit(1)
        }
        let folder = URL(fileURLWithPath: csvPath).deletingLastPathComponent()
        if let dump { try? FileManager.default.createDirectory(at: dump, withIntermediateDirectories: true) }

        var right = 0, wrong = 0, none = 0
        for line in csv.split(separator: "\n").dropFirst() {
            let f = line.split(separator: ",").map(String.init)
            guard f.count >= 3, let total = Double(f[1]), let gallons = Double(f[2]) else { continue }
            let url = folder.appendingPathComponent(f[0])
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                print("?? \(f[0]): couldn't open")
                continue
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32)
                .flatMap(CGImagePropertyOrientation.init) ?? .up

            var rowCount = 0
            if let dump {
                SegmentDisplayReader.debugSink = { ink, w, h, slots, top, bottom in
                    var px = ink.map { $0 ? UInt8(0) : UInt8(255) }
                    for slot in slots {
                        for x in slot where x >= 0 && x < w { px[top * w + x] = 160; px[bottom * w + x] = 160 }
                        for y in top...bottom {
                            if slot.lowerBound >= 0 { px[y * w + slot.lowerBound] = 160 }
                            if slot.upperBound - 1 < w { px[y * w + slot.upperBound - 1] = 160 }
                        }
                    }
                    rowCount += 1
                    writeGray(px, w, h, to: dump.appendingPathComponent("\(f[0])-row\(rowCount).png"))
                }
            }
            let start = Date()
            var crop: CGRect?
            if !whole, f.count >= 8, let x = Double(f[4]), let y = Double(f[5]), let w = Double(f[6]), let h = Double(f[7]) {
                crop = CGRect(x: x, y: y, width: w, height: h)
            }
            let result = SegmentDisplayReader.read(image, orientation: orientation, crop: crop)
            let seconds = Date().timeIntervalSince(start)
            var mark = "--"
            if let r = result.reading {
                if abs(r.total - total) < 0.001 && abs(r.gallons - gallons) < 0.0005 {
                    mark = "OK"; right += 1
                } else {
                    mark = "XX"; wrong += 1
                }
                print(String(format: "%@ %-18@ %.3f gal $%.2f  (want %.3f $%.2f)  %.1fs",
                             mark, f[0], r.gallons, r.total, gallons, total, seconds))
            } else {
                none += 1
                print(String(format: "-- %-18@ no reading  (want %.3f $%.2f)  %.1fs", f[0], gallons, total, seconds))
            }
            if verbose || result.reading == nil || mark == "XX" {
                for note in result.notes { print("     \(note)") }
            }
            if let dump { dumpMasks(image, orientation, crop: crop, name: f[0], to: dump) }
        }
        print("\n\(right) right, \(wrong) wrong, \(none) no reading")
    }

    static func writeGray(_ pixels: [UInt8], _ w: Int, _ h: Int, to out: URL) {
        var pixels = pixels
        let provider = CGDataProvider(data: Data(bytes: &pixels, count: pixels.count) as CFData)!
        guard let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                               space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, cg, nil)
        CGImageDestinationFinalize(dest)
    }

    /// Saves each display candidate's ink mask as a PNG.
    static func dumpMasks(_ image: CGImage, _ orientation: CGImagePropertyOrientation, crop: CGRect?,
                          name: String, to folder: URL) {
        var whole = CIImage(cgImage: image).oriented(orientation)
        if let crop, let cropped = PumpPhotoReader.cropped(whole, to: crop) { whole = cropped }
        let displays = SegmentDisplayReader.numberAreas(in: whole) + SegmentDisplayReader.rectangles(in: whole) + [whole]
        for (i, display) in displays.enumerated() {
            guard let gray = SegmentDisplayReader.grayscale(display, height: SegmentDisplayReader.workingHeight) else { continue }
            let mask = SegmentDisplayReader.inkMask(width: gray.width, height: gray.height, pixels: gray.pixels)
            var pixels = mask.ink.map { $0 ? UInt8(0) : UInt8(255) }
            let provider = CGDataProvider(data: Data(bytes: &pixels, count: pixels.count) as CFData)!
            guard let cg = CGImage(width: mask.width, height: mask.height, bitsPerComponent: 8, bitsPerPixel: 8,
                                   bytesPerRow: mask.width, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil,
                                   shouldInterpolate: false, intent: .defaultIntent) else { continue }
            let out = folder.appendingPathComponent("\(name)-\(i).png")
            if let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, cg, nil)
                CGImageDestinationFinalize(dest)
            }
        }
    }
}

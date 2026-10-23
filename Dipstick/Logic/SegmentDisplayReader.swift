//
//  SegmentDisplayReader.swift
//  Dipstick
//

import Accelerate
import Foundation
import CoreImage
import Vision

/// Reads a gas pump's seven-segment display from a photo, without general
/// text recognition (which misreads segment digits; see PumpPhotoReader).
///
/// 1. Find the display: where text recognition sees numbers (it finds them
///    reliably even when it misreads them), rectangles in the photo
///    (straightened), and the photo itself as a fallback.
/// 2. Even out lighting (each pixel against its neighborhood's brightness)
///    and split dark segments from the light background.
/// 3. Find the rows of digits: the tallest is the sale, the next gallons
///    (a third, if any, the price per gallon).
/// 4. Undo the digits' slant, split each row into digits and decimal points.
/// 5. For each digit, measure which of the 7 segments are lit and match the
///    pattern of each digit; every digit keeps its close runners-up.
/// 6. Build the readings and keep the one whose numbers check out best
///    (an x.xx9 price explains the total, plausible price, fewest doubts).
///
/// Foundation, Core Image and Vision only, so tools can run it on a Mac.
nonisolated enum SegmentDisplayReader {
    // MARK: Results

    struct DigitRead {
        /// Candidates, best first; cost 0 is a perfect segment match.
        var candidates: [(character: Character, cost: Double)]
        /// Read from a narrow piece (a "1", or a sliver of the display's frame).
        var isNarrow = false
        var best: Character { candidates.first?.character ?? "?" }
        /// How sure: the gap between the best and second-best match.
        var margin: Double { candidates.count > 1 ? candidates[1].cost - candidates[0].cost : 9 }
    }

    struct RowRead {
        var digits: [DigitRead]
        /// Index of the digit a decimal point follows, if one was seen.
        var pointAfter: Int?
        var height: Int
        /// A digit touches the edge of the image: it may be cut off, so the
        /// number may be missing a digit ("10.872" read as "0.872").
        var isClipped = false

        /// Each digit with its runners-up and costs, for tuning.
        var detail: String {
            digits.map { d in
                d.candidates.prefix(3).map { "\($0.character)\(String(format: "%.2f", $0.cost))" }.joined(separator: ",")
            }.joined(separator: " | ")
        }

        var text: String {
            var s = ""
            for (i, d) in digits.enumerated() {
                s.append(d.best)
                if pointAfter == i { s.append(".") }
            }
            return s
        }
    }

    struct Result {
        let reading: PumpReadingParser.Reading?
        /// Digit positions the reader was unsure of, per row (0 = sale, 1 =
        /// gallons), counted from the right, for highlighting on review.
        let unsureDigits: [Int: Set<Int>]
        /// What was read from each display candidate, for tuning.
        let notes: [String]
    }

    static let context = CIContext(options: [.workingColorSpace: NSNull()])

    #if DEBUG
    /// Tools only: receives each straightened row with its digit slots.
    nonisolated(unsafe) static var debugSink: ((_ ink: [Bool], _ width: Int, _ height: Int,
                                                _ slots: [Range<Int>], _ top: Int, _ bottom: Int) -> Void)?
    #endif

    // MARK: Entry point

    /// - Parameter crop: where to look (the scan frame), as fractions of the
    ///   oriented photo from the top left; nil searches the whole photo.
    static func read(_ image: CGImage, orientation: CGImagePropertyOrientation = .up,
                     crop: CGRect? = nil, expectedPrice: Double? = nil) -> Result {
        let whole = CIImage(cgImage: image).oriented(orientation)
        var regions = [whole]
        if let crop, let cropped = PumpPhotoReader.cropped(whole, to: crop) { regions = [cropped] }

        var displays: [(name: String, image: CIImage)] = []
        for (r, region) in regions.enumerated() {
            let name = r == 0 && crop != nil ? "crop" : "photo"
            for (i, area) in numberAreas(in: region).enumerated() {
                displays.append(("\(name) numbers\(i)", area))
            }
            for (i, rect) in rectangles(in: region).enumerated() {
                displays.append(("\(name) rect\(i)", rect))
            }
            displays.append((name, region))
        }

        var best: (candidate: Candidate, name: String)?
        var notes: [String] = []
        for display in displays {
            guard let rows = decode(display.image) else {
                notes.append("\(display.name): no rows")
                continue
            }
            let candidate = bestCandidate(rows: rows, expectedPrice: expectedPrice)
            notes.append("\(display.name): " + rows.map(\.text).joined(separator: " / ")
                         + (candidate.map { " → \($0.describe)" } ?? " → –"))
            if ProcessInfo.processInfo.environment["SEGMENT_DETAIL"] != nil {
                for row in rows { notes.append("        " + row.detail) }
            }
            if let candidate, candidate.cost <= maxCost, best == nil || candidate.rank < best!.candidate.rank {
                best = (candidate, display.name)
            }
            // A clean reading that checks out: no need to look further.
            if let b = best?.candidate, b.reading.confidence >= .priceFits, b.cost < 0.4 { break }
        }
        return Result(reading: best?.candidate.reading,
                      unsureDigits: best?.candidate.unsure ?? [:], notes: notes)
    }

    /// Live frames: just the scan frame's crop and the display rectangles in
    /// it (no text recognition, to keep up with the camera).
    static func readLive(_ image: CIImage, expectedPrice: Double?) -> Result {
        var best: Candidate?
        for display in rectangles(in: image) + [image] {
            guard let rows = decode(display),
                  let candidate = bestCandidate(rows: rows, expectedPrice: expectedPrice),
                  candidate.cost <= maxCost else { continue }
            if best == nil || candidate.rank < best!.rank { best = candidate }
        }
        return Result(reading: best?.reading, unsureDigits: best?.unsure ?? [:], notes: [])
    }

    // MARK: Finding the display

    /// Areas around numbers that text recognition finds, sized to take in the
    /// row above or below (a sale row, then gallons under it, or the other
    /// way round).
    static func numberAreas(in image: CIImage) -> [CIImage] {
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        let e = image.extent
        let boxes = (request.results ?? [])
            .filter { ($0.topCandidates(1).first?.string ?? "").filter(\.isNumber).count >= 2 }
            .map(\.boundingBox)  // 0–1, origin at the bottom left
            .sorted { $0.height > $1.height }
            .prefix(3)
        var areas: [CIImage] = []
        for box in boxes {
            // This row is the top one (gallons below), or the bottom one.
            for (above, below) in [(0.6, 2.0), (2.4, 0.6)] {
                let rect = CGRect(x: box.minX - box.width * 0.5, y: box.minY - box.height * below,
                                  width: box.width * 2.0, height: box.height * (1 + above + below))
                    .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                guard !rect.isEmpty else { continue }
                areas.append(image.cropped(to: CGRect(x: e.minX + rect.minX * e.width, y: e.minY + rect.minY * e.height,
                                                      width: rect.width * e.width, height: rect.height * e.height)))
            }
        }
        return areas
    }

    /// Straightened crops of likely display windows, most likely first.
    static func rectangles(in image: CIImage) -> [CIImage] {
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return [] }
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.15   // short side / long side
        request.maximumAspectRatio = 0.8
        request.minimumSize = 0.15
        request.minimumConfidence = 0.4
        request.quadratureTolerance = 25
        request.maximumObservations = 6
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        let e = image.extent
        func point(_ p: CGPoint) -> CIVector {
            CIVector(x: e.minX + p.x * e.width, y: e.minY + p.y * e.height)
        }
        return (request.results ?? []).compactMap { r in
            let filter = CIFilter(name: "CIPerspectiveCorrection")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(point(r.topLeft), forKey: "inputTopLeft")
            filter?.setValue(point(r.topRight), forKey: "inputTopRight")
            filter?.setValue(point(r.bottomLeft), forKey: "inputBottomLeft")
            filter?.setValue(point(r.bottomRight), forKey: "inputBottomRight")
            return filter?.outputImage
        }
    }

    // MARK: Pixels

    struct Mask {
        let width: Int, height: Int
        var ink: [Bool]
        subscript(x: Int, y: Int) -> Bool { ink[y * width + x] }
    }

    /// Working height for a display; digits end up roughly 50–100 px tall.
    static let workingHeight = 260

    /// Grayscale pixels, top row first.
    static func grayscale(_ image: CIImage, height: Int) -> (width: Int, height: Int, pixels: [UInt8])? {
        let e = image.extent
        guard e.width >= 8, e.height >= 8, e.width.isFinite else { return nil }
        let scale = Double(height) / e.height
        let width = max(8, Int((e.width * scale).rounded()))
        guard width < 4000 else { return nil }
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
            .transformed(by: CGAffineTransform(scaleX: Double(width) / e.width, y: scale))
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        var pixels = [UInt8](repeating: 0, count: width * height)
        context.render(scaled, toBitmap: &pixels, rowBytes: width,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .L8, colorSpace: nil)
        return (width, height, pixels)
    }

    /// Segment ink: each pixel compared with the brightest pixel within a
    /// window a bit wider than a segment is thick. Thin dark strokes stand
    /// out; large even areas (the LCD's gray, a dark frame, glare) don't,
    /// whatever their brightness. `lightSegments` reads lit segments on a
    /// dark display instead.
    static func inkMask(width w: Int, height h: Int, pixels: [UInt8], lightSegments: Bool = false) -> Mask {
        var values = lightSegments ? pixels.map { 255 - $0 } : pixels
        let r = max(4, h / 20)
        // Brightest pixel nearby (Accelerate's max filter: fast even in
        // unoptimized builds).
        var nearbyMax = [UInt8](repeating: 0, count: w * h)
        values.withUnsafeMutableBytes { source in
            nearbyMax.withUnsafeMutableBytes { destination in
                var src = vImage_Buffer(data: source.baseAddress, height: vImagePixelCount(h),
                                        width: vImagePixelCount(w), rowBytes: w)
                var dst = vImage_Buffer(data: destination.baseAddress, height: vImagePixelCount(h),
                                        width: vImagePixelCount(w), rowBytes: w)
                _ = vImageMax_Planar8(&src, &dst, nil, 0, 0, vImagePixelCount(2 * r + 1),
                                      vImagePixelCount(2 * r + 1), vImage_Flags(kvImageEdgeExtend))
            }
        }
        var ratio = [Double](repeating: 1, count: w * h)
        for i in 0..<(w * h) {
            ratio[i] = Double(values[i]) / max(Double(nearbyMax[i]), 8)
        }
        let threshold = min(max(otsu(ratio), 0.45), 0.8)
        var mask = Mask(width: w, height: h, ink: ratio.map { $0 < threshold })
        eraseLongLines(&mask)
        return mask
    }

    /// The display's frame and other edges: straight runs of ink far longer
    /// than any digit segment. Erased so they don't merge with the digits
    /// (a frame touching the digits' tops makes every top bar look lit).
    static func eraseLongLines(_ mask: inout Mask) {
        let w = mask.width, h = mask.height
        let maxAcross = max(12, w * 3 / 10), maxDown = max(12, h * 7 / 10)
        var erase = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            var start = 0
            for x in 0...w {
                if x < w && mask[x, y] { continue }
                if x - start > maxAcross { for i in start..<x { erase[y * w + i] = true } }
                start = x + 1
            }
        }
        for x in 0..<w {
            var start = 0
            for y in 0...h {
                if y < h && mask[x, y] { continue }
                if y - start > maxDown { for i in start..<y { erase[i * w + x] = true } }
                start = y + 1
            }
        }
        for i in 0..<(w * h) where erase[i] { mask.ink[i] = false }
    }

    private static func otsu(_ values: [Double]) -> Double {
        let bins = 200, top = 2.0
        var histogram = [Double](repeating: 0, count: bins)
        for v in values { histogram[min(bins - 1, max(0, Int(v / top * Double(bins))))] += 1 }
        let total = Double(values.count)
        let sumAll = histogram.enumerated().reduce(0.0) { $0 + Double($1.offset) * $1.element }
        var weightBelow = 0.0, sumBelow = 0.0, bestVariance = -1.0, bestBin = bins / 2
        for i in 0..<bins {
            weightBelow += histogram[i]
            if weightBelow == 0 { continue }
            let weightAbove = total - weightBelow
            if weightAbove == 0 { break }
            sumBelow += Double(i) * histogram[i]
            let meanBelow = sumBelow / weightBelow, meanAbove = (sumAll - sumBelow) / weightAbove
            let variance = weightBelow * weightAbove * (meanBelow - meanAbove) * (meanBelow - meanAbove)
            if variance > bestVariance { bestVariance = variance; bestBin = i }
        }
        return (Double(bestBin) + 1) / Double(bins) * top
    }

    // MARK: Rows and digits

    /// The digit rows of one display, top first, or nil if it doesn't look
    /// like a pump display (fewer than two rows of digits).
    static func decode(_ image: CIImage) -> [RowRead]? {
        guard let gray = grayscale(image, height: workingHeight) else { return nil }
        // Dark segments on a light LCD (most pumps), else lit segments.
        for lightSegments in [false, true] {
            let mask = inkMask(width: gray.width, height: gray.height, pixels: gray.pixels,
                               lightSegments: lightSegments)
            let bands = rowBands(mask)
            guard bands.count >= 2 else { continue }
            let rows = bands.compactMap { readRow(mask, rows: $0) }
            if rows.count >= 2 { return rows }
        }
        return nil
    }

    /// Horizontal bands of ink tall enough to be digits: the tallest two (or
    /// three, for a price row) in top-to-bottom order.
    static func rowBands(_ mask: Mask) -> [Range<Int>] {
        let w = mask.width, h = mask.height
        let margin = w / 50
        var counts = [Int](repeating: 0, count: h)
        for y in 0..<h {
            var n = 0
            for x in margin..<(w - margin) where mask[x, y] { n += 1 }
            // Window edges and other full-width lines aren't digits.
            counts[y] = n > (w - 2 * margin) * 7 / 10 ? 0 : n
        }
        // Rows of digits stand well above the thin background ink (frame
        // edges, labels' stray pixels) that runs through every row.
        let threshold = max(2, w / 60, (counts.max() ?? 0) * 15 / 100)
        var bands: [Range<Int>] = []
        var start: Int?, gap = 0
        for y in 0...h {
            let on = y < h && counts[y] >= threshold
            if on {
                if start == nil { start = y }
                gap = 0
            } else if let s = start {
                gap += 1
                if gap > 2 || y == h {
                    bands.append(s..<(y - gap + 1))
                    start = nil
                    gap = 0
                }
            }
        }
        let tall = bands.filter { $0.count >= h / 9 }
        let chosen = tall.sorted { $0.count > $1.count }.prefix(3)
        // A third row only if it's about as tall as gallons (a price row).
        var rows = Array(chosen.prefix(2))
        if chosen.count == 3, let second = rows.last, chosen[2].count * 10 >= second.count * 7 {
            rows.append(chosen[2])
        }
        return rows.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// One row's digits: undo the slant, split into columns of ink, classify.
    static func readRow(_ mask: Mask, rows: Range<Int>) -> RowRead? {
        let h = rows.count
        guard h >= 10 else { return nil }
        let shear = bestShear(mask, rows: rows)
        let pad = Int(ceil(abs(shear) * Double(h))) + 2
        let width = mask.width + 2 * pad

        // The row, straightened: x' = x + shear·(y − middle).
        var band = [Bool](repeating: false, count: width * h)
        let middle = Double(rows.lowerBound + rows.upperBound) / 2
        for y in rows {
            let shift = Int((shear * (Double(y) - middle)).rounded())
            for x in 0..<mask.width where mask[x, y] {
                let nx = x + shift + pad
                if nx >= 0 && nx < width { band[(y - rows.lowerBound) * width + nx] = true }
            }
        }
        func inkAt(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < width && y >= 0 && y < h && band[y * width + x] }

        // Column runs.
        var columnInk = [Int](repeating: 0, count: width)
        for x in 0..<width { for y in 0..<h where inkAt(x, y) { columnInk[x] += 1 } }
        var runs: [Range<Int>] = []
        var start: Int?
        for x in 0...width {
            let on = x < width && columnInk[x] > 0
            if on, start == nil { start = x }
            if !on, let s = start { runs.append(s..<x); start = nil }
        }

        // Vertical extent of a run's ink.
        func extent(_ run: Range<Int>) -> (top: Int, bottom: Int, pixels: Int) {
            var top = h, bottom = -1, pixels = 0
            for x in run { for y in 0..<h where inkAt(x, y) {
                top = min(top, y); bottom = max(bottom, y); pixels += 1
            } }
            return (top, bottom, pixels)
        }

        // Drop specks.
        var pieces = runs.compactMap { run -> (run: Range<Int>, top: Int, bottom: Int, pixels: Int)? in
            let e = extent(run)
            guard e.pixels >= max(4, h / 6) else { return nil }
            return (run, e.top, e.bottom, e.pixels)
        }
        guard !pieces.isEmpty else { return nil }

        // Segment digits are mostly hollow; solid blobs are label plates
        // ("Sale $", "Gallons") or shadows.
        func density(_ p: (run: Range<Int>, top: Int, bottom: Int, pixels: Int)) -> Double {
            Double(p.pixels) / Double(p.run.count * (p.bottom - p.top + 1))
        }
        func median(_ values: [Int]) -> Int { values.sorted()[values.count / 2] }

        // Digit size: the typical tall, hollow piece.
        let tall = pieces.filter { $0.bottom - $0.top + 1 >= h / 2 && density($0) < 0.6 }
        guard !tall.isEmpty else { return nil }
        let typicalHeight = median(tall.map { $0.bottom - $0.top + 1 })
        let sized = tall.filter { abs(($0.bottom - $0.top + 1) - typicalHeight) <= typicalHeight / 5 }
        let top = median(sized.map(\.top)), bottom = median(sized.map(\.bottom))
        let digitHeight = bottom - top + 1
        guard digitHeight >= 10 else { return nil }

        let wide = sized.filter { $0.run.count >= digitHeight * 3 / 10 }
        let digitWidth = wide.isEmpty ? Double(digitHeight) * 0.55 : Double(median(wide.map(\.run.count)))

        // Near the image's left or right edge (allowing for the slant).
        let edgeMargin = Int(abs(shear) * Double(h) / 2) + 2
        func atEdge(_ run: Range<Int>) -> Bool {
            run.lowerBound <= pad + edgeMargin || run.upperBound >= pad + mask.width - edgeMargin
        }
        pieces.removeAll { piece in
            let pieceHeight = piece.bottom - piece.top + 1
            return pieceHeight > digitHeight * 135 / 100                // taller than the digits
                || (Double(piece.run.count) >= digitWidth * 0.45 && density(piece) > 0.6)  // a plate
        }

        // A thin upright piece whose ink carries on well above or below the
        // row is the display's frame (or a label's edge), not a "1": a
        // segment "1" ends where the digits do.
        func continuesOutside(_ run: Range<Int>) -> Bool {
            let reach = max(3, digitHeight * 2 / 5)
            func inkRows(_ ys: StrideThrough<Int>) -> Int {
                ys.filter { y in
                    guard y >= 0 && y < mask.height else { return false }
                    let shift = Int((shear * (Double(y) - middle)).rounded())
                    return (run.lowerBound - 1...run.upperBound).contains { x in
                        let ox = x - shift - pad
                        return ox >= 0 && ox < mask.width && mask[ox, y]
                    }
                }.count
            }
            let bandTop = rows.lowerBound + top, bandBottom = rows.lowerBound + bottom
            let above = inkRows(stride(from: bandTop - 2, through: bandTop - reach, by: -1))
            let below = inkRows(stride(from: bandBottom + 2, through: bandBottom + reach, by: 1))
            return Double(max(above, below)) >= Double(reach - 1) * 0.7
        }
        for piece in pieces where Double(piece.run.count) < digitWidth * 0.4
            && piece.bottom - piece.top + 1 >= digitHeight * 7 / 10 && continuesOutside(piece.run) {
            for x in piece.run { for y in 0..<h { band[y * width + x] = false } }
        }
        pieces.removeAll { piece in
            !piece.run.contains { x in (0..<h).contains { inkAt(x, $0) } }
        }
        // A thin line at the very edge that isn't a digit's height is the
        // frame too; anything digit-sized at the edge may be a cut-off digit.
        pieces.removeAll { atEdge($0.run) && Double($0.run.count) < digitWidth * 0.3
            && $0.bottom - $0.top + 1 < digitHeight * 7 / 10 }
        let isClipped = pieces.contains { atEdge($0.run) && $0.bottom - $0.top + 1 >= digitHeight / 2 }

        // Fit a grid of evenly spaced digit slots, right-aligned on a digit,
        // and read each slot as a digit or blank. Slivers and specks that
        // don't line up with the grid are ignored.
        let tallPieces = pieces.filter { $0.bottom - $0.top + 1 >= digitHeight / 2 }
        guard !tallPieces.isEmpty else { return nil }
        let edges = Array(Set(tallPieces.map(\.run.upperBound))).sorted()
        let rightEdges = Array(edges.suffix(4))
        // Spacing between digits, measured: gaps between right edges (or
        // half a gap, across a blank or a missed digit).
        var pitches = Set<Int>()
        for (a, b) in zip(edges, edges.dropFirst()) {
            let gap = b - a
            for d in [gap, gap / 2] where Double(d) >= digitWidth * 0.95 && Double(d) <= digitWidth * 1.9 {
                for jitter in -2...2 { pitches.insert(d + jitter) }
            }
        }
        guard let grid = fitGrid(rightEdges: rightEdges, pitches: pitches.sorted(), digitWidth: digitWidth,
                                 top: top, bottom: bottom, width: width, inkAt: inkAt) else { return nil }
        let digits = grid.digits
        #if DEBUG
        debugSink?(band, width, h, grid.slots, top, bottom)
        #endif
        guard !digits.isEmpty else { return nil }
        return RowRead(digits: digits, pointAfter: nil, height: digitHeight, isClipped: isClipped)
    }

    /// Most digit slots a row can have (999.99, 99.999).
    static let maxSlots = 5

    /// The best grid of digit slots: tries slot widths, spacings and right
    /// edges, reads each slot as its best digit or blank, and keeps the
    /// cheapest. Returns the digits, left to right (leading blanks dropped).
    static func fitGrid(rightEdges: [Int], pitches measured: [Int], digitWidth: Double, top: Int, bottom: Int, width: Int,
                        inkAt: (Int, Int) -> Bool) -> (digits: [DigitRead], slots: [Range<Int>])? {
        // Ink to the right of the grid: a digit left out.
        var inkRightOf = [Int](repeating: 0, count: width + 1)
        for x in stride(from: width - 1, through: 0, by: -1) {
            var n = 0
            for y in top...bottom where inkAt(x, y) { n += 1 }
            inkRightOf[x] = inkRightOf[x + 1] + n
        }
        let segmentArea = Double(bottom - top + 1) * digitWidth * 0.12

        var cache: [Int: (digits: [(character: Character, cost: Double)], blank: Double)] = [:]
        func read(_ x0: Int, _ x1: Int) -> (digits: [(character: Character, cost: Double)], blank: Double) {
            let key = x0 * 10_000 + x1
            if let hit = cache[key] { return hit }
            let coverage = segmentCoverage(x0..<x1, top: top, bottom: bottom, inkAt: inkAt)
            let blank = "abcdefg".reduce(0.0) { $0 + max(0, (coverage[$1] ?? 0) - 0.3) }
            let result = (rank(coverage), blank)
            cache[key] = result
            return result
        }

        var best: (cost: Double, slots: [[(character: Character, cost: Double)]], ranges: [Range<Int>])?
        for scale in [0.9, 1.0, 1.1] {
            let w = max(4, Int((digitWidth * scale).rounded()))
            let step = max(1, w / 20)
            // Spacing measured between the digits; a broad search only if
            // there's nothing to measure (one wide digit in the row).
            let pitches = measured.isEmpty
                ? Array(stride(from: Int(Double(w) * 1.05), through: Int(Double(w) * 1.75), by: step))
                : measured.filter { $0 > w }
            for pitch in pitches {
                for edge in rightEdges {
                    for right in [edge - 2, edge, edge + 2] where right > w && right <= width {
                        var slots: [(digits: [(character: Character, cost: Double)], blank: Double)] = []
                        for i in 0..<maxSlots {
                            let x1 = right - i * pitch, x0 = x1 - w
                            guard x0 >= 0 else { break }
                            slots.append(read(x0, x1))
                        }
                        guard slots.count >= 3 else { continue }
                        let leftOut = Double(inkRightOf[min(width, right + w / 4)]) / segmentArea * 0.5
                        // k digits from the right, then blanks.
                        for k in 3...slots.count {
                            var cost = leftOut
                            for i in 0..<slots.count {
                                cost += i < k ? (slots[i].digits.first?.cost ?? 9) : slots[i].blank
                            }
                            if best == nil || cost < best!.cost {
                                let ranges = (0..<k).map { (right - $0 * pitch - w)..<(right - $0 * pitch) }
                                best = (cost, slots.prefix(k).map(\.digits).reversed(), ranges.reversed())
                            }
                        }
                    }
                }
            }
        }
        return best.map { ($0.slots.map { DigitRead(candidates: $0) }, $0.ranges) }
    }

    /// The slant (horizontal shift per row) that best separates the digits:
    /// the most empty columns between them.
    static func bestShear(_ mask: Mask, rows: Range<Int>) -> Double {
        let middle = Double(rows.lowerBound + rows.upperBound) / 2
        var best = (shear: 0.0, empty: -1)
        let pad = Int(ceil(0.35 * Double(rows.count))) + 2
        var occupied = [Bool](repeating: false, count: mask.width + 2 * pad)
        for step in -14...6 {
            let shear = Double(step) * 0.025
            for i in occupied.indices { occupied[i] = false }
            var minX = Int.max, maxX = Int.min, count = 0
            for y in rows {
                let shift = Int((shear * (Double(y) - middle)).rounded()) + pad
                let row = y * mask.width
                for x in 0..<mask.width where mask.ink[row + x] {
                    let nx = x + shift
                    if !occupied[nx] { occupied[nx] = true; count += 1 }
                    if nx < minX { minX = nx }
                    if nx > maxX { maxX = nx }
                }
            }
            guard minX <= maxX else { return 0 }
            let empty = (maxX - minX + 1) - count
            if empty > best.empty || (empty == best.empty && abs(shear) < abs(best.shear)) {
                best = (shear, empty)
            }
        }
        return best.shear
    }

    // MARK: Segments

    /// Segments a–g: a top, b top right, c bottom right, d bottom,
    /// e bottom left, f top left, g middle.
    static let patterns: [(Character, Set<Character>)] = [
        ("0", ["a", "b", "c", "d", "e", "f"]),
        ("1", ["b", "c"]),
        ("2", ["a", "b", "d", "e", "g"]),
        ("3", ["a", "b", "c", "d", "g"]),
        ("4", ["b", "c", "f", "g"]),
        ("5", ["a", "c", "d", "f", "g"]),
        ("6", ["a", "c", "d", "e", "f", "g"]),
        ("6", ["c", "d", "e", "f", "g"]),       // 6 without its top bar
        ("7", ["a", "b", "c"]),
        ("7", ["a", "b", "c", "f"]),            // 7 with a hook
        ("8", ["a", "b", "c", "d", "e", "f", "g"]),
        ("9", ["a", "b", "c", "d", "f", "g"]),
        ("9", ["a", "b", "c", "f", "g"]),       // 9 without its bottom bar
    ]

    /// How much of each segment's area is lit, 0–1.
    static func segmentCoverage(_ cols: Range<Int>, top: Int, bottom: Int,
                                inkAt: (Int, Int) -> Bool) -> [Character: Double] {
        let w = Double(cols.count), h = Double(bottom - top + 1)
        // Slots are estimates: the side segments may sit a little outside.
        func x(_ u: Double) -> Int { max(0, cols.lowerBound + Int((u * w).rounded(.down))) }
        func y(_ v: Double) -> Int { top + Int(v * h) }
        // Horizontal segment: share of its columns with ink in its band.
        func horizontal(_ v0: Double, _ v1: Double) -> Double {
            let xs = x(0.25)..<max(x(0.25) + 1, x(0.75)), ys = y(v0)..<max(y(v0) + 1, y(v1))
            var lit = 0
            for cx in xs {
                for cy in ys where inkAt(cx, cy) { lit += 1; break }
            }
            return Double(lit) / Double(xs.count)
        }
        // Vertical segment: share of its rows with ink in its strip.
        func vertical(_ u0: Double, _ u1: Double, _ v0: Double, _ v1: Double) -> Double {
            let xs = x(u0)..<max(x(u0) + 1, x(u1)), ys = y(v0)..<max(y(v0) + 1, y(v1))
            var lit = 0
            for cy in ys {
                for cx in xs where inkAt(cx, cy) { lit += 1; break }
            }
            return Double(lit) / Double(ys.count)
        }
        return [
            "a": horizontal(0, 0.2),
            "g": horizontal(0.4, 0.6),
            "d": horizontal(0.8, 1.0),
            "f": vertical(-0.1, 0.35, 0.12, 0.4),
            "b": vertical(0.65, 1.08, 0.12, 0.4),
            "e": vertical(-0.1, 0.35, 0.6, 0.88),
            "c": vertical(0.65, 1.08, 0.6, 0.88),
        ]
    }

    static func classify(_ cols: Range<Int>, top: Int, bottom: Int, inkAt: (Int, Int) -> Bool) -> DigitRead {
        let coverage = segmentCoverage(cols, top: top, bottom: bottom, inkAt: inkAt)
        return DigitRead(candidates: rank(coverage))
    }

    /// Candidate digits for measured coverage, best first (one entry per digit).
    static func rank(_ coverage: [Character: Double]) -> [(character: Character, cost: Double)] {
        var bestPerDigit: [Character: Double] = [:]
        for (digit, lit) in patterns {
            var cost = 0.0
            for segment in "abcdefg" {
                let c = coverage[segment] ?? 0
                cost += lit.contains(segment) ? max(0, 0.8 - c) : max(0, c - 0.3)
            }
            bestPerDigit[digit] = min(bestPerDigit[digit] ?? .infinity, cost)
        }
        return bestPerDigit.map { ($0.key, $0.value) }.sorted { $0.1 < $1.1 }
    }

    /// A narrow piece is a "1": its two right-hand segments, with a small
    /// break between them. A narrow piece with no break is more likely a
    /// sliver of the display's frame, so it's a less certain "1".
    static func classifyNarrow(_ cols: Range<Int>, top: Int, bottom: Int, inkAt: (Int, Int) -> Bool) -> DigitRead {
        let h = bottom - top + 1
        let lit = (top...bottom).filter { y in cols.contains { inkAt($0, y) } }.count
        let coverage = Double(lit) / Double(h)
        let middle = (top + h * 2 / 5)...(top + h * 3 / 5)
        let hasBreak = middle.contains { y in !cols.contains { inkAt($0, y) } }
        let cost = max(0, 0.8 - coverage) + (hasBreak ? 0 : 0.5)
        return DigitRead(candidates: [("1", cost), ("7", cost + 1.2)], isNarrow: true)
    }

    // MARK: Choosing the reading

    /// Readings whose digits match their segment patterns this poorly are
    /// more likely specks and labels than a display: better no reading.
    static let maxCost = 2.5

    struct Candidate {
        let reading: PumpReadingParser.Reading
        let cost: Double
        let unsure: [Int: Set<Int>]
        /// Lower is better: segment cost, less a bonus when the numbers check
        /// out, so a close runner-up digit that makes them fit can win.
        var rank: Double {
            switch reading.confidence {
            case .checked: cost - 1.5
            case .priceFits, .priceFitsCorrected: cost - 0.9
            case .priceInferred: cost
            }
        }
        var describe: String {
            String(format: "%.3f gal $%.2f $%.3f (cost %.2f)", reading.gallons, reading.total,
                   reading.pricePerGallon, cost)
        }
    }

    /// Numbers a row could be: the best digits plus close runners-up at
    /// unsure positions, with their total cost. Anchored on the decimal point
    /// when one was seen: exactly `decimals` digits after it and at most
    /// `maxWhole` before; extra digits at the ends (frame edges, specks) are
    /// trimmed at a small cost.
    static func values(of row: RowRead, decimals: Int, maxWhole: Int,
                       limit: Int = 16) -> [(value: Double, cost: Double, changed: Set<Int>)] {
        var spans: [(digits: ArraySlice<DigitRead>, penalty: Double)] = []
        let all = row.digits[...]
        if let p = row.pointAfter, all.count - 1 - p >= decimals {
            let end = p + 1 + decimals
            let trailing = all[end...].reduce(0.0) { $0 + ($1.isNarrow ? 0.05 : 0.35) }
            // Whole digits: as many as fit, or fewer (a speck or frame sliver
            // read as a leading "1").
            for wholeStart in max(0, p + 1 - maxWhole)...p {
                let leading = all[..<wholeStart].reduce(0.0) { $0 + ($1.isNarrow ? 0.05 : 0.35) }
                spans.append((all[wholeStart..<end], trailing + leading))
            }
        } else {
            // No usable point: the whole row, or without an end digit.
            spans.append((all, row.pointAfter == nil ? 0 : 0.3))
            if all.count > decimals + 1 {
                spans.append((all.dropLast(), (all.last!.isNarrow ? 0.05 : 0.4)))
                spans.append((all.dropFirst(), (all.first!.isNarrow ? 0.05 : 0.4)))
            }
        }

        var results: [(value: Double, cost: Double, changed: Set<Int>)] = []
        for span in spans {
            let digits = Array(span.digits)
            let count = digits.count
            guard count >= decimals + 1, count <= decimals + maxWhole else { continue }
            var options: [(digits: [Character], cost: Double, changed: Set<Int>)] = [
                (digits.map(\.best), span.penalty + digits.reduce(0) { $0 + ($1.candidates.first?.cost ?? 0) }, []),
            ]
            for (i, digit) in digits.enumerated() {
                let base = digit.candidates.first?.cost ?? 0
                let alternatives = digit.candidates.dropFirst().prefix(2).filter { $0.cost - base < 1.0 }
                guard !alternatives.isEmpty else { continue }
                var added: [(digits: [Character], cost: Double, changed: Set<Int>)] = []
                for alternative in alternatives {
                    added += options.map { option in
                        var d = option.digits
                        d[i] = alternative.character
                        return (d, option.cost + alternative.cost - base, option.changed.union([count - 1 - i]))
                    }
                }
                options = Array((options + added).sorted { $0.cost < $1.cost }.prefix(limit))
            }
            for option in options {
                var text = String(option.digits)
                text.insert(".", at: text.index(text.endIndex, offsetBy: -decimals))
                if let value = Double(text) { results.append((value, option.cost, option.changed)) }
            }
        }
        return results
    }

    static func bestCandidate(rows: [RowRead], expectedPrice: Double?) -> Candidate? {
        // A cut-off digit could make any number: better no reading.
        guard !rows[0].isClipped, !rows[1].isClipped else { return nil }
        let totals = values(of: rows[0], decimals: 2, maxWhole: 3)
        let gallons = values(of: rows[1], decimals: 3, maxWhole: 2)
        let prices = rows.count > 2 ? values(of: rows[2], decimals: 3, maxWhole: 2) : []
        var best: Candidate?
        for t in totals where PumpReadingParser.totalRange.contains(t.value) {
            for g in gallons where PumpReadingParser.gallonsRange.contains(g.value) {
                let implied = t.value / g.value
                guard PumpReadingParser.isPlausible(price: implied, expected: expectedPrice) else { continue }
                var reading: PumpReadingParser.Reading
                var cost = t.cost + g.cost
                if let p = prices.first(where: { abs(g.value * $0.value - t.value) <= PumpReadingParser.tolerance }) {
                    reading = .init(gallons: g.value, total: t.value, pricePerGallon: p.value, confidence: .checked)
                    cost += p.cost
                } else if let nine = PumpReadingParser.nineTenthsPrice(gallons: g.value, total: t.value) {
                    reading = .init(gallons: g.value, total: t.value, pricePerGallon: nine, confidence: .priceFits)
                } else {
                    reading = .init(gallons: g.value, total: t.value,
                                    pricePerGallon: (implied * 1000).rounded() / 1000, confidence: .priceInferred)
                }
                let candidate = Candidate(reading: reading, cost: cost, unsure: [0: t.changed, 1: g.changed])
                if best == nil || candidate.rank < best!.rank { best = candidate }
            }
        }
        return best
    }
}

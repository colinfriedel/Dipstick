//
//  PumpReadingParser.swift
//  Dipstick
//

import Foundation

/// Finds gallons and the sale total (and price per gallon, if shown) in text
/// read from a gas pump's display.
///
/// The usual case is the pump's main screen, which shows only gallons (3
/// decimals, 9.768) and the total (2 decimals, 60.06); the price is worked out
/// as total ÷ gallons and must be close to the car's recent price. Pump
/// prices almost always end in 9/10 of a cent, so a pair whose total some
/// x.xx9 price explains ($6.999 × 10.555 = $73.874 → $73.87) beats one no
/// such price explains. And when a total doesn't fit, one digit is tried as
/// its usual segment misread (a "7" missing its top bar reads as "1"): if
/// exactly one such fix fits an x.xx9 price, it's used ($73.81 → $73.87). If a price
/// (3 decimals or "6.14 9/10") is also visible, gallons × price must match the
/// total to the cent, which makes the reading "checked".
///
/// Segment displays' decimal points are tiny and often not read ("7387" for
/// $73.87), so a 3–5 digit number without one is also tried as a total (2
/// decimals) or gallons (3 decimals), but only alongside a number that kept
/// its point, unless the car's recent price is known to check against.
///
/// Foundation only, so tools/scan_pump_photo.swift can reuse it on a Mac.
nonisolated enum PumpReadingParser {
    struct Reading: Equatable {
        enum Confidence: Int, Comparable {
            /// Gallons and total only; price worked out from them.
            case priceInferred
            /// As `priceFits`, after fixing one misread digit of the total.
            case priceFitsCorrected
            /// Gallons and total only, and an x.xx9 price explains the total.
            case priceFits
            /// A displayed price agrees: gallons × price = total.
            case checked
            static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
        }
        var gallons: Double
        var total: Double
        var pricePerGallon: Double
        var confidence: Confidence
    }

    struct Number: Equatable {
        let value: Double
        /// Digits after the decimal point.
        let decimals: Int
        /// Lowercased text of the line it came from, for label hints.
        let line: String
        /// The decimal point wasn't read; `decimals` is a guess.
        var missingPoint = false
    }

    // Plausible ranges for one fill-up.
    /// Any amount the display can show; the price check does the filtering.
    static let gallonsRange = 0.001...40.0
    static let priceRange = 1.5...12.0
    static let totalRange = 1.0...400.0
    /// Pumps round the total to the cent; allow a little slack for that.
    static let tolerance = 0.015
    /// How far total ÷ gallons may be from the car's recent price per gallon.
    static let expectedPriceTolerance = 0.30

    /// - Parameter expectedPrice: the car's recent average price per gallon,
    ///   if known. Readings implying a very different price are rejected.
    static func parse(_ lines: [String], expectedPrice: Double? = nil) -> Reading? {
        let numbers = lines.flatMap(numbers(in:))
        return bestReading(in: numbers, expectedPrice: expectedPrice)
    }

    static func isPlausible(price: Double, expected: Double?) -> Bool {
        guard priceRange.contains(price) else { return false }
        guard let expected, expected > 0 else { return true }
        return abs(price - expected) / expected <= expectedPriceTolerance
    }

    // MARK: Finding numbers

    /// Numbers with a decimal point in one line of recognized text, after
    /// fixing common misreads of segment-display digits.
    static func numbers(in rawLine: String) -> [Number] {
        let line = normalize(rawLine)
        let lower = rawLine.lowercased()
        var found: [Number] = []

        // "6.14 9/10" or "6.14⁹" style prices: 2 decimals plus a tenth of a cent.
        let ninePattern = #"(\d{1,2})\.(\d{2})\s*(\d)\s*/\s*10"#
        if let regex = try? NSRegularExpression(pattern: ninePattern) {
            for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                let whole = substring(line, match.range(at: 1))
                let cents = substring(line, match.range(at: 2))
                let tenth = substring(line, match.range(at: 3))
                if let value = Double("\(whole).\(cents)\(tenth)") {
                    found.append(Number(value: value, decimals: 3, line: lower))
                }
            }
        }

        let pattern = #"(?<![\d.])(\d{1,3})\.(\d{1,3})(?![\d])"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                let whole = substring(line, match.range(at: 1))
                let fraction = substring(line, match.range(at: 2))
                if let value = Double("\(whole).\(fraction)") {
                    found.append(Number(value: value, decimals: fraction.count, line: lower))
                }
            }
        }

        // "7387" with the point missed: try it as $73.87 and as 7.387 gal.
        let undotted = #"(?<![\d.,])(\d{3,5})(?![\d.,])"#
        if let regex = try? NSRegularExpression(pattern: undotted) {
            for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                guard let digits = Double(substring(line, match.range(at: 1))) else { continue }
                found.append(Number(value: digits / 100, decimals: 2, line: lower, missingPoint: true))
                found.append(Number(value: digits / 1000, decimals: 3, line: lower, missingPoint: true))
            }
        }
        return found
    }

    /// Fixes letters that OCR commonly reads in place of segment-display
    /// digits ("9.76B" → "9.768"). Only swaps a letter that touches a digit
    /// and has no letter beside it, so labels like "9.768GAL" stay intact.
    /// "S" (often a misread "$") and "G" (from "GAL") are deliberately left alone.
    static func normalize(_ line: String) -> String {
        let swaps: [Character: Character] = [
            "O": "0", "o": "0", "D": "0", "Q": "0",
            "I": "1", "l": "1", "|": "1",
            "Z": "2", "z": "2",
            "B": "8",
        ]
        let chars = Array(line)
        var result: [Character] = []
        for (index, char) in chars.enumerated() {
            let before: Character = index > 0 ? chars[index - 1] : " "
            let after: Character = index + 1 < chars.count ? chars[index + 1] : " "
            if char == "," {
                // A comma is a decimal point only between digits ("9,768").
                result.append(before.isNumber && after.isNumber ? "." : char)
            } else if let swap = swaps[char],
                      before.isNumber || before == "." || after.isNumber || after == ".",
                      !before.isLetter, !after.isLetter {
                result.append(swap)
            } else {
                result.append(char)
            }
        }
        return String(result)
    }

    // MARK: Choosing the reading

    static func bestReading(in numbers: [Number], expectedPrice: Double? = nil) -> Reading? {
        let unique = deduplicated(numbers)
        var best: (reading: Reading, score: Int)?

        func consider(_ reading: Reading, score: Int) {
            if let current = best,
               (current.reading.confidence, current.score) >= (reading.confidence, score) { return }
            best = (reading, score)
        }

        for g in unique where gallonsRange.contains(g.value) {
            for t in unique where t != g && totalRange.contains(t.value) {
                // Both points missing is too easy to match by chance without
                // a recent price to check against.
                if g.missingPoint && t.missingPoint && expectedPrice == nil { continue }
                // With a displayed price: the strong, self-checking case.
                for p in unique where p != g && p != t && isPlausible(price: p.value, expected: expectedPrice) {
                    if abs(g.value * p.value - t.value) <= tolerance {
                        let reading = Reading(gallons: g.value, total: t.value, pricePerGallon: p.value, confidence: .checked)
                        consider(reading, score: score(gallons: g, total: t, price: p))
                    }
                }
                // The main screen's usual case: gallons and total only.
                guard g.decimals == 3, t.decimals == 2 else { continue }
                let implied = t.value / g.value
                let plausible = isPlausible(price: implied, expected: expectedPrice)
                let ninePrice = plausible ? nineTenthsPrice(gallons: g.value, total: t.value) : nil
                if plausible {
                    let reading = Reading(gallons: g.value, total: t.value,
                                          pricePerGallon: ninePrice ?? (implied * 1000).rounded() / 1000,
                                          confidence: ninePrice == nil ? .priceInferred : .priceFits)
                    consider(reading, score: score(gallons: g, total: t, price: nil))
                }
                // No x.xx9 price explains it (or the price is way off, like
                // $13.87 for $73.87): maybe a segment digit was misread.
                if ninePrice == nil, let fixed = correctedTotal(gallons: g.value, total: t.value,
                                                                expectedPrice: expectedPrice) {
                    let reading = Reading(gallons: g.value, total: fixed.total, pricePerGallon: fixed.price,
                                          confidence: .priceFitsCorrected)
                    consider(reading, score: score(gallons: g, total: t, price: nil))
                }
            }
        }
        return best?.reading
    }

    /// An x.xx9 price that, times the gallons, rounds to the total; nil if
    /// none does.
    static func nineTenthsPrice(gallons: Double, total: Double) -> Double? {
        guard gallons > 0 else { return nil }
        let low = (total - 0.005) / gallons, high = (total + 0.005) / gallons
        let cents = ((low - 0.009) * 100 - 1e-9).rounded(.up)
        let price = ((cents / 100 + 0.009) * 1000).rounded() / 1000
        return price >= low - 1e-9 && price <= high + 1e-9 ? price : nil
    }

    /// What each segment digit is most often misread as, the other way round:
    /// a "1" may really be a "7" whose top bar wasn't seen, and so on.
    static let segmentMisreads: [Character: [Character]] = [
        "1": ["7"], "7": ["1"], "3": ["8"], "8": ["3", "0", "6", "9"],
        "0": ["8"], "6": ["5", "8"], "5": ["6"], "9": ["8"],
    ]

    /// The total with one digit changed to a likely misread, if exactly one
    /// such change makes an x.xx9 price explain it (with a plausible price).
    static func correctedTotal(gallons: Double, total: Double,
                               expectedPrice: Double?) -> (total: Double, price: Double)? {
        let digits = Array(String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), total))
        var fits: [(total: Double, price: Double)] = []
        for (index, digit) in digits.enumerated() {
            for swap in segmentMisreads[digit] ?? [] {
                var changed = digits
                changed[index] = swap
                guard let value = Double(String(changed)), totalRange.contains(value),
                      isPlausible(price: value / gallons, expected: expectedPrice),
                      let price = nineTenthsPrice(gallons: gallons, total: value) else { continue }
                fits.append((value, price))
            }
        }
        return fits.count == 1 ? fits[0] : nil
    }

    /// Prefers numbers in their usual shape and next to their usual labels.
    private static func score(gallons: Number, total: Number, price: Number?) -> Int {
        var score = 0
        if gallons.decimals == 3 { score += 2 }
        if total.decimals == 2 { score += 2 }
        if let price, price.decimals == 3 { score += 1 }
        if gallons.line.contains("gal") && !gallons.line.contains("/gal") { score += 2 }
        if ["sale", "total", "amount", "$"].contains(where: total.line.contains) { score += 2 }
        if let price, ["price", "/gal", "per", "unit"].contains(where: price.line.contains) { score += 1 }
        // A number whose point was read beats a guessed one.
        score -= 3 * [gallons.missingPoint, total.missingPoint, price?.missingPoint ?? false].filter { $0 }.count
        return score
    }

    private static func deduplicated(_ numbers: [Number]) -> [Number] {
        var seen = Set<String>()
        // Keep a number whose point was read over the same value guessed.
        let ordered = numbers.filter { !$0.missingPoint } + numbers.filter(\.missingPoint)
        return ordered.filter { seen.insert("\($0.value)|\($0.decimals)").inserted }
    }

    private static func substring(_ string: String, _ range: NSRange) -> String {
        Range(range, in: string).map { String(string[$0]) } ?? ""
    }
}

/// Collects readings from successive camera frames and accepts one only once
/// it has been seen enough times, so a single misread frame can't fill the form.
nonisolated struct PumpReadingVoter {
    static let checkedFramesNeeded = 2
    /// For a reading whose price works out to an x.xx9 pump price.
    static let fitsFramesNeeded = 3

    private var counts: [String: (reading: PumpReadingParser.Reading, frames: Int)] = [:]

    /// Adds one frame's reading; returns a reading once it's confirmed.
    mutating func add(_ reading: PumpReadingParser.Reading?) -> PumpReadingParser.Reading? {
        // A price that's merely plausible is too easy to get from stray
        // numbers on screen (1.055 gal and a $7.42 elsewhere); live reading
        // needs the stronger checks. The capture button still accepts it.
        guard let reading, reading.confidence > .priceInferred else { return nil }
        let key = String(format: "%.3f|%.2f|%.3f", reading.gallons, reading.total, reading.pricePerGallon)
        let frames = (counts[key]?.frames ?? 0) + 1
        counts[key] = (reading, frames)
        let needed = reading.confidence == .checked ? Self.checkedFramesNeeded : Self.fitsFramesNeeded
        return frames >= needed ? reading : nil
    }
}

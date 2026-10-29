//
//  ScheduleReader.swift
//  Dipstick
//

import Foundation
import CoreGraphics
import ImageIO
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads a maintenance schedule from owner's manual pages (photos,
/// screenshots, PDFs). Two layouts are understood:
///
/// - **Grid**: mileage columns across the top (10, 20, 30… or 7,500,
///   15,000…), a service on each row, and a mark (•, ✓, I, R) in the
///   columns where it's due. Read from where each piece of text sits on the
///   page, so nothing is guessed: the interval is the spacing of the marks.
/// - **List**: lines like "Replace engine oil every 7,500 miles or 12
///   months". Read by rules, or by Apple's on-device language model when
///   the phone has it, with every number checked against the page.
///
/// Anything doubtful (one mark only, numbers not found on the page) is
/// marked for you to check before it's saved.
nonisolated enum ScheduleReader {
    struct Item: Identifiable, Equatable {
        var id = UUID()
        var name: String
        /// The service it counts as when logged ("Oil change").
        var serviceType: String
        var everyMiles: Int?
        var everyMonths: Int?
        var firstMiles: Int?
        var firstMonths: Int?
        var note: String?
        var unsure = false
        var include = true

        var hasInterval: Bool { [everyMiles, everyMonths, firstMiles, firstMonths].contains { $0 != nil } }
    }

    /// A piece of text and where it is, in page fractions from the top left.
    struct Box: Equatable {
        var text: String
        var minX: Double, maxX: Double, minY: Double, maxY: Double
        var midX: Double { (minX + maxX) / 2 }
        var midY: Double { (minY + maxY) / 2 }
        var height: Double { maxY - minY }
    }

    /// Vision's boxes (origin bottom left) as `Box`es (origin top left).
    static func boxes(from textBoxes: [ReceiptParser.TextBox]) -> [Box] {
        textBoxes.map { b in
            let xs = [b.topLeft.x, b.topRight.x, b.bottomLeft.x, b.bottomRight.x].map(Double.init)
            let ys = [b.topLeft.y, b.topRight.y, b.bottomLeft.y, b.bottomRight.y].map(Double.init)
            return Box(text: b.text, minX: xs.min()!, maxX: xs.max()!, minY: 1 - ys.max()!, maxY: 1 - ys.min()!)
        }
    }

    // MARK: Ink

    /// A small grayscale copy of the page, for seeing which table cells have
    /// a mark in them (dots, checks, X's and letters are all just ink).
    struct InkMap: Sendable, Equatable {
        var width: Int
        var height: Int
        /// Brightness per pixel, row by row from the top: 0 black, 255 white.
        var pixels: [UInt8]

        init(width: Int, height: Int, pixels: [UInt8]) {
            (self.width, self.height, self.pixels) = (width, height, pixels)
        }

        /// The page drawn upright (photo orientation applied) at up to
        /// `maxPixels` on the long side.
        init?(imageData: Data, maxPixels: Int = 1_600) {
            guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                  ] as CFDictionary) else { return nil }
            let (w, h) = (image.width, image.height)
            var pixels = [UInt8](repeating: 255, count: w * h)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                              bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                              bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                context.setFillColor(gray: 1, alpha: 1)
                context.fill(CGRect(x: 0, y: 0, width: w, height: h))
                context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            self.init(width: w, height: h, pixels: pixels)
        }

        /// Share of dark pixels in a region given in page fractions from the
        /// top left. Light shading (alternate row colors) doesn't count.
        func darkness(minX: Double, maxX: Double, minY: Double, maxY: Double) -> Double {
            let x0 = max(0, Int(minX * Double(width))), x1 = min(width, Int(maxX * Double(width)))
            let y0 = max(0, Int(minY * Double(height))), y1 = min(height, Int(maxY * Double(height)))
            guard x1 > x0, y1 > y0 else { return 0 }
            var dark = 0
            for y in y0..<y1 {
                let row = y * width
                for x in x0..<x1 where pixels[row + x] < 110 { dark += 1 }
            }
            return Double(dark) / Double((x1 - x0) * (y1 - y0))
        }
    }

    // MARK: Grid

    /// One word of a box and where it sits, splitting boxes that span
    /// several columns ("•  •  •") by character position.
    struct Token: Equatable {
        var text: String
        var x: Double
        var y: Double
        var height: Double
    }

    static func tokens(_ boxes: [Box]) -> [Token] {
        boxes.flatMap { box -> [Token] in
            let text = box.text
            guard text.count > 0 else { return [] }
            var result: [Token] = []
            var start: String.Index?
            for index in text.indices {
                let isSpace = text[index].isWhitespace
                if !isSpace, start == nil { start = index }
                if (isSpace || text.index(after: index) == text.endIndex), let s = start {
                    let end = isSpace ? index : text.endIndex
                    let a = Double(text.distance(from: text.startIndex, to: s))
                    let b = Double(text.distance(from: text.startIndex, to: end))
                    let n = Double(text.count)
                    let x = box.minX + (box.maxX - box.minX) * ((a + b) / 2) / n
                    result.append(Token(text: String(text[s..<end]), x: x, y: box.midY, height: box.height))
                    start = nil
                }
            }
            return result
        }
    }

    /// Numbers as written in a header: "10", "7,500", "15K", "120", and
    /// "7.5" or "22.5" in a table of thousands. Kept in tenths so 7.5 survives
    /// until the scale is known.
    static func headerNumber(_ text: String) -> Int? {
        var t = text.trimmingCharacters(in: CharacterSet(charactersIn: "()[]*:"))
        if t.hasSuffix(".") { t.removeLast() }
        var scale = 10.0
        if t.lowercased().hasSuffix("k") { t.removeLast(); scale = 10_000 }
        t = t.replacingOccurrences(of: ",", with: "")
        guard !t.isEmpty, t.allSatisfy({ $0.isNumber || $0 == "." }), t.filter({ $0 == "." }).count <= 1,
              let value = Double(t), value > 0 else { return nil }
        return Int((value * scale).rounded())
    }

    struct Column: Equatable {
        var x: Double
        var miles: Int?
        var months: Int?
    }

    /// Rows of tokens at the same height.
    static func rows(_ tokens: [Token]) -> [[Token]] {
        var rows: [[Token]] = []
        for token in tokens.sorted(by: { $0.y < $1.y }) {
            if let last = rows.last?.first, abs(last.y - token.y) < min(last.height, token.height) * 0.6 {
                rows[rows.count - 1].append(token)
            } else {
                rows.append([token])
            }
        }
        return rows.map { $0.sorted { $0.x < $1.x } }
    }

    /// The table's columns: a row of at least four increasing numbers
    /// (mileage, or months), with a second such row lined up under it if
    /// there's one. nil when the page isn't a grid.
    static func columns(_ tokens: [Token], pageText: String) -> (columns: [Column], headerYs: [Double])? {
        let lower = pageText.lowercased()
        struct Header { var y: Double; var xs: [Double]; var values: [Int]; var kind: String }
        var headers: [Header] = []
        for row in rows(tokens) {
            let numbers = row.compactMap { t in headerNumber(t.text).map { (t.x, $0) } }
            guard numbers.count >= 4, zip(numbers, numbers.dropFirst()).allSatisfy({ $0.1 < $1.1 }) else { continue }
            let line = row.map(\.text).joined(separator: " ").lowercased()
            let kind = line.contains("km") || line.contains("kilomet") ? "km"
                : line.contains("month") || line.contains("mo.") ? "months"
                : line.contains("mile") || line.contains("mi.") || line.contains(" mi") ? "miles" : ""
            headers.append(Header(y: row[0].y, xs: numbers.map(\.0), values: numbers.map(\.1), kind: kind))
        }
        guard !headers.isEmpty else { return nil }
        let milesRow = headers.first { $0.kind == "miles" } ?? headers.first { $0.kind == "" }
        let monthsRow = headers.first { $0.kind == "months" }
        guard let base = milesRow ?? monthsRow else { return nil }

        // Mileage written in thousands ("10 20 30" under "x 1,000 miles").
        // Header numbers are in tenths (see `headerNumber`).
        var milesScale = 0.1
        if let milesRow, milesRow.values.max()! < 10_000 {
            let thousands = lower.contains("1,000") || lower.contains("1000") || lower.contains("thousand")
                || lower.contains("x1") || milesRow.values.max()! <= 3_000
            guard thousands else { return nil }
            milesScale = 100
        }
        let step = zip(base.xs, base.xs.dropFirst()).map { $1 - $0 }.sorted()[(base.xs.count - 1) / 2]
        func value(in row: Header?, near x: Double) -> Int? {
            guard let row else { return nil }
            return zip(row.xs, row.values).first { abs($0.0 - x) < step * 0.45 }?.1
        }
        let columns = base.xs.map { x in
            Column(x: x, miles: value(in: milesRow, near: x).map { Int((Double($0) * milesScale).rounded()) },
                   months: value(in: monthsRow, near: x).map { $0 / 10 })
        }
        return (columns, headers.map(\.y))
    }

    /// Reads a grid table. Returns nil when the page isn't one. With the
    /// page's `ink`, a cell counts as marked when it has ink in it;
    /// without, only marks the text recognition read (•, ✓, I, R…).
    static func readGrid(_ boxes: [Box], ink: InkMap? = nil, known: [String] = []) -> [Item]? {
        let pageText = boxes.map(\.text).joined(separator: "\n")
        let all = tokens(boxes)
        guard let (columns, headerYs) = columns(all, pageText: pageText), columns.count >= 4 else { return nil }
        let xs = columns.map(\.x)
        let step = zip(xs, xs.dropFirst()).map { $1 - $0 }.sorted()[(xs.count - 1) / 2]
        let tableTop = headerYs.min()!
        let gridLeft = xs.first! - step * 0.55

        // Labels: text left of the first column, below the header.
        let labelBoxes = boxes.filter { box in
            box.maxX < gridLeft && box.midY > tableTop
                && !headerYs.contains { abs($0 - box.midY) < box.height * 0.6 }
        }
        var labels: [(text: String, y: Double, height: Double)] = []
        for box in labelBoxes.sorted(by: { $0.midY < $1.midY }) {
            if let i = labels.indices.last, abs(labels[i].y - box.midY) < min(labels[i].height, box.height) * 0.6 {
                labels[i].text += " " + box.text
            } else {
                labels.append((box.text, box.midY, box.height))
            }
        }

        // Marks: ink in a row's cell under a column.
        var marksByLabel: [Int: Set<Int>] = [:]
        if let ink {
            for (i, label) in labels.enumerated() {
                let half = label.height * 0.3
                for (c, x) in xs.enumerated()
                where ink.darkness(minX: x - step * 0.3, maxX: x + step * 0.3,
                                   minY: label.y - half, maxY: label.y + half) > 0.012 {
                    marksByLabel[i, default: []].insert(c)
                }
            }
        }
        // And marks the text recognition read.
        for token in all where token.y > tableTop + 0.003 && token.text.count <= 3 && !headerYs.contains(where: { abs($0 - token.y) < token.height * 0.6 }) {
            guard let col = xs.firstIndex(where: { abs($0 - token.x) < step * 0.45 }),
                  let label = labels.indices.min(by: { abs(labels[$0].y - token.y) < abs(labels[$1].y - token.y) }),
                  abs(labels[label].y - token.y) < labels[label].height * 1.1 else { continue }
            marksByLabel[label, default: []].insert(col)
        }
        guard marksByLabel.count >= 2 else { return nil }

        // A label line with no marks that continues the line above (starts
        // in lowercase, or the line above ends mid-phrase) is a wrapped name;
        // others are headings and notes.
        var names: [Int: String] = Dictionary(uniqueKeysWithValues: marksByLabel.keys.map { ($0, labels[$0].text) })
        for i in labels.indices where marksByLabel[i] == nil && i > 0 && names[i - 1] != nil {
            let above = names[i - 1]!.trimmingCharacters(in: .whitespaces).lowercased()
            let continues = labels[i].text.first?.isLowercase == true
                || [",", "&", "-", "/"].contains(where: above.hasSuffix)
                || [" and", " or", " the", " of"].contains(where: above.hasSuffix)
            guard continues, abs(labels[i - 1].y - labels[i].y) < labels[i].height * 1.8 else { continue }
            names[i - 1] = names[i - 1]! + " " + labels[i].text
        }

        return marksByLabel.keys.sorted().compactMap { label -> Item? in
            let cols = marksByLabel[label]!.sorted()
            var item = Item(name: cleanName(names[label]!), serviceType: "")
            guard !item.name.isEmpty else { return nil }
            item.serviceType = RecordImport.serviceName(item.name, known: known)
            let miles = interval(cols.compactMap { columns[$0].miles })
            let months = interval(cols.compactMap { columns[$0].months })
            (item.everyMiles, item.firstMiles) = (miles.every, miles.first)
            (item.everyMonths, item.firstMonths) = (months.every, months.first)
            item.unsure = miles.unsure || months.unsure
            // A note in the name ("every 3 years") overrides the grid.
            if let stated = listInterval(names[label]!) {
                item.everyMonths = stated.everyMonths ?? item.everyMonths
                item.everyMiles = stated.everyMiles ?? item.everyMiles
            }
            return item
        }
    }

    /// The interval from the columns marked: the usual spacing of the
    /// marks, and where they start if that's later (first at 120,000 mi,
    /// then every 60,000).
    static func interval(_ values: [Int]) -> (every: Int?, first: Int?, unsure: Bool) {
        let v = Array(Set(values)).sorted()
        guard let start = v.first else { return (nil, nil, false) }
        guard v.count >= 2 else { return (nil, start, true) }
        let gaps = zip(v, v.dropFirst()).map { $1 - $0 }
        let counts = Dictionary(gaps.map { ($0, 1) }, uniquingKeysWith: +)
        let every = counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }!.key
        // Uneven spacing (a mark missed or misread) gets checked.
        let uneven = gaps.contains { $0 != every }
        return (every, start == every ? nil : start, uneven)
    }

    // MARK: List

    struct Stated: Equatable {
        var everyMiles: Int?
        var everyMonths: Int?
        var firstMiles: Int?
        var firstMonths: Int?
    }

    /// "every 7,500 miles or 12 months", "Every 3 years", "first at 120,000
    /// miles, then every 60,000 miles" → the numbers. nil if none.
    static func listInterval(_ line: String) -> Stated? {
        let lower = line.lowercased()
        let milesPattern = #/(\d{1,3}(?:,\d{3})+|\d+(?:\.\d+)?\s*k|\d+)\s*(?:miles?|mi\b)/#
        let monthsPattern = #/(\d+)\s*(?:months?|mos?\b)/#
        let yearsPattern = #/(\d+)\s*(?:years?|yrs?\b)/#
        func number(_ text: Substring) -> Int? {
            var t = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
            var scale = 1.0
            if t.hasSuffix("k") { t = String(t.dropLast()).trimmingCharacters(in: .whitespaces); scale = 1_000 }
            return Double(t).map { Int(($0 * scale).rounded()) }
        }
        let miles = lower.matches(of: milesPattern).compactMap { number($0.output.1) }.filter { $0 >= 500 }
        let months = lower.matches(of: monthsPattern).compactMap { Int($0.output.1) }
            + lower.matches(of: yearsPattern).compactMap { Int($0.output.1).map { $0 * 12 } }
        guard !miles.isEmpty || !months.isEmpty else { return nil }
        let thenEvery = lower.contains("then") || lower.contains("thereafter") || lower.contains("after that")
        var stated = Stated()
        if thenEvery && miles.count >= 2 { (stated.firstMiles, stated.everyMiles) = (miles[0], miles[1]) } else { stated.everyMiles = miles.first }
        if thenEvery && months.count >= 2 { (stated.firstMonths, stated.everyMonths) = (months[0], months[1]) } else { stated.everyMonths = months.first }
        return stated
    }

    /// Reads list lines with rules: each line with an interval is an item,
    /// named by the words before the interval.
    static func readList(_ text: String, known: [String] = []) -> [Item] {
        var items: [Item] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let stated = listInterval(line) else { continue }
            let lower = line.lowercased()
            let cut = ["every", "each", "at ", "first", "initial", "after"].compactMap { lower.range(of: $0)?.lowerBound }
                + [line.firstIndex(where: \.isNumber)].compactMap { $0 }
            let name = cleanName(String(line[..<(cut.min() ?? line.endIndex)]))
            guard name.filter(\.isLetter).count >= 3 else { continue }
            items.append(Item(name: name, serviceType: RecordImport.serviceName(name, known: known),
                              everyMiles: stated.everyMiles, everyMonths: stated.everyMonths,
                              firstMiles: stated.firstMiles, firstMonths: stated.firstMonths))
        }
        return items
    }

    /// A grid with lines written under it ("Replace brake fluid every 3
    /// years regardless of mileage"): the line's interval wins for that
    /// service, since the grid can only show what fits its columns.
    static func withNotes(_ grid: [Item], from text: String, known: [String]) -> [Item] {
        var items = grid
        for note in readList(text, known: known) {
            guard let i = items.firstIndex(where: { $0.serviceType.caseInsensitiveCompare(note.serviceType) == .orderedSame }) else { continue }
            items[i].everyMiles = note.everyMiles
            items[i].everyMonths = note.everyMonths
            items[i].firstMiles = note.firstMiles
            items[i].firstMonths = note.firstMonths
            items[i].unsure = false
        }
        return items
    }

    /// "• Replace engine oil:" → "Replace engine oil"; "Spark plugs: replace"
    /// → "Replace spark plugs"; ALL CAPS → Sentence case.
    static func cleanName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
        if let colon = name.firstIndex(of: ":") {
            let part = name[..<colon].trimmingCharacters(in: .whitespaces)
            let action = name[name.index(after: colon)...].trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
            let verbs = ["replace", "inspect", "check", "rotate", "change", "clean", "adjust", "lubricate", "test", "flush"]
            if verbs.contains(action.lowercased()) {
                name = action.prefix(1).uppercased() + action.dropFirst().lowercased() + " " + part.prefix(1).lowercased() + part.dropFirst()
            } else if action.isEmpty {
                name = part
            }
        }
        name = name.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if name == name.uppercased(), name.contains(where: \.isLetter) {
            name = name.lowercased()
            name = name.prefix(1).uppercased() + name.dropFirst()
        }
        return name
    }

    /// Every number in a model's answer must be on the page; otherwise the
    /// item is marked to check.
    static func check(_ item: inout Item, against page: RecordImport.Grounding) {
        let miles = [item.everyMiles, item.firstMiles].compactMap { $0 }
        let months = [item.everyMonths, item.firstMonths].compactMap { $0 }
        let milesFound = miles.allSatisfy { page.has(number: $0) || ($0 % 1_000 == 0 && page.has(number: $0 / 1_000)) }
        let monthsFound = months.allSatisfy { page.has(number: $0) || ($0 % 12 == 0 && page.has(number: $0 / 12)) }
        if !milesFound || !monthsFound { item.unsure = true }
    }

    // MARK: Finding the schedule in a whole manual

    static let maxScannedPages = 30

    /// Which pages of a PDF to read, from each page's text. Short PDFs
    /// (a saved schedule page or two) are read whole. In a full manual, the
    /// pages that look like the schedule: they mention maintenance or
    /// service, and give intervals in miles, months or km, or have a row of
    /// mileage columns; then the page after each, since schedules run on.
    static func schedulePageIndexes(_ texts: [String]) -> [Int] {
        guard texts.count > 6 else { return Array(texts.indices) }
        let hasText = texts.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 }
        guard hasText else { return Array(texts.indices.prefix(maxScannedPages)) }

        let scored = texts.enumerated().map { index, text -> (Int, Int) in
            let lower = text.lowercased()
            var score = 0
            if lower.contains("maintenance schedule") || lower.contains("service schedule")
                || lower.contains("maintenance minder") || lower.contains("scheduled maintenance") { score += 3 }
            if lower.contains("maintenance") || lower.contains("service interval") { score += 1 }
            let intervals = lower.matches(of: #/\d[\d,]*\s*(?:miles|mi\b|km|months)/#).count
            score += min(intervals, 6)
            if lower.contains("x 1,000") || lower.contains("x1,000") || lower.contains("× 1,000") { score += 3 }
            for verb in ["replace", "inspect", "rotate"] where lower.contains(verb) { score += 1 }
            return (index, score)
        }
        let best = scored.map(\.1).max() ?? 0
        guard best >= 5 else { return [] }
        // Pages close to the best one, and the page after each, since a schedule often runs on.
        var picked = Set<Int>()
        for (index, score) in scored where score >= max(5, best - 4) {
            picked.insert(index)
            if index + 1 < texts.count { picked.insert(index + 1) }
        }
        return picked.sorted().prefix(12).map { $0 }
    }

    // MARK: Reading pages

    struct Page: Sendable {
        var boxes: [Box]
        var text: String
        var preview: Data?
        var ink: InkMap?
    }

    /// Reads every page: grids by position, other pages as lists (with the
    /// language model when the phone has it). Items from all pages are
    /// joined, the same name read twice kept once.
    static func read(_ pages: [Page], known: [String]) async -> [Item] {
        var items: [Item] = []
        for page in pages {
            var found: [Item]
            if let grid = readGrid(page.boxes, ink: page.ink, known: known), grid.count >= 2 {
                found = withNotes(grid, from: page.text, known: known)
            } else {
                found = readList(page.text, known: known)
                #if canImport(FoundationModels)
                if #available(iOS 26.0, macOS 26.0, *), found.count < 2,
                   var modelItems = await ModelScheduleReader.read(page.text, known: known), !modelItems.isEmpty {
                    let grounding = RecordImport.Grounding(page.text)
                    for i in modelItems.indices { check(&modelItems[i], against: grounding) }
                    found = modelItems
                }
                #endif
            }
            for item in found where item.hasInterval
            && !items.contains(where: { $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) {
                items.append(item)
            }
        }
        return items
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
private enum ModelScheduleReader {
    @Generable(description: "A car maintenance schedule")
    struct Found {
        @Guide(description: "Each maintenance item, in the order listed")
        var items: [FoundItem]
    }

    @Generable
    struct FoundItem {
        @Guide(description: "What to do, as written, e.g. Replace engine oil")
        var name: String
        @Guide(description: "The interval exactly as written, e.g. every 7,500 miles or 12 months; first at 120,000 miles then every 60,000 miles")
        var interval: String
    }

    static func read(_ text: String, known: [String]) async -> [ScheduleReader.Item]? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: """
            You read text from a car owner's manual and list its maintenance schedule: each item and its interval. \
            Copy intervals exactly as written; never calculate or guess numbers. Leave out items with no interval.
            """)
        guard let response = try? await session.respond(to: "Text:\n" + String(text.prefix(3_000)), generating: Found.self,
                                                        options: GenerationOptions(samplingMode: .greedy)) else { return nil }
        return response.content.items.compactMap { found in
            guard let stated = ScheduleReader.listInterval(found.interval) else { return nil }
            let name = ScheduleReader.cleanName(found.name)
            guard !name.isEmpty else { return nil }
            return ScheduleReader.Item(name: name, serviceType: RecordImport.serviceName(name, known: known),
                                       everyMiles: stated.everyMiles, everyMonths: stated.everyMonths,
                                       firstMiles: stated.firstMiles, firstMonths: stated.firstMonths)
        }
    }
}
#endif

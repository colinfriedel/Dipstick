//
//  ReceiptParser.swift
//  Dipstick
//

import Foundation
import CoreGraphics

/// Turns the lines of text read from a receipt photo or an order screenshot
/// (Amazon and the like) into items, subtotal, tax, shipping and total.
///
/// Rules, not guesses: amounts are found by their labels ("SUB-TOTAL",
/// "Estimated tax", "Grand Total"), items are lines with a price above the
/// subtotal, and a register's code line ("1004892  1 EA  $12.99 EA") gives
/// the next item its SKU and quantity. `Receipt.checks` says whether the
/// numbers add up, which decides between this and the on-device model's
/// reading (see `ReceiptReader`). No UIKit or Vision, so tools can run it.
nonisolated enum ReceiptParser {
    struct Item: Equatable, Identifiable {
        var id = UUID()
        var name: String
        var partNumber: String?
        var quantity: Int = 1
        /// What all of them cost together, before tax.
        var lineTotal: Double

        static func == (a: Item, b: Item) -> Bool {
            a.name == b.name && a.partNumber == b.partNumber && a.quantity == b.quantity
                && abs(a.lineTotal - b.lineTotal) < 0.005
        }
    }

    struct Receipt: Equatable {
        var items: [Item] = []
        var subtotal: Double?
        var tax: Double?
        var shipping: Double?
        var total: Double?

        var itemsTotal: Double { items.reduce(0) { $0 + $1.lineTotal } }

        /// Items add up to the subtotal (when there is one), and subtotal +
        /// tax + shipping to the total (when there is one).
        var checks: Bool {
            guard !items.isEmpty else { return false }
            let subtotal = self.subtotal ?? itemsTotal
            if abs(itemsTotal - subtotal) > 0.015 { return false }
            if let total, abs(subtotal + (tax ?? 0) + (shipping ?? 0) - total) > 0.015 { return false }
            return true
        }
    }

    // MARK: Amounts

    /// "$12.99", "12.99", ",99", "15,96", "$1,234.56", "-$3.00".
    static let amountPattern = #"(?<![\w.,])-?\$?\s?(\d{1,3}(?:,\d{3})*|\d*)[.,](\d{2})(?![\d])"#

    /// Money amounts on a line, left to right.
    static func amounts(in line: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: amountPattern) else { return [] }
        return regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { match in
            guard let wholeRange = Range(match.range(at: 1), in: line),
                  let centsRange = Range(match.range(at: 2), in: line),
                  let full = Range(match.range, in: line) else { return nil }
            let whole = line[wholeRange].replacingOccurrences(of: ",", with: "")
            guard let value = Double("\(whole.isEmpty ? "0" : whole).\(line[centsRange])") else { return nil }
            return line[full].hasPrefix("-") ? -value : value
        }
    }

    private enum Label { case subtotal, tax, shipping, total, ignore }

    /// What a summary line is, by its words.
    private static func label(of line: String) -> Label? {
        let l = line.lowercased()
        if l.contains("subtotal") || l.contains("sub-total") || l.contains("sub total") || l.contains("total before tax") {
            return l.contains("before tax") && !l.contains("subtotal") ? .ignore : .subtotal
        }
        if l.contains("tax") { return .tax }
        if l.contains("shipping") || l.contains("handling") || l.contains("delivery fee") { return .shipping }
        if l.contains("total") { return .total }
        return nil
    }

    /// Payment, card and store-info lines: never items.
    private static let noise = [
        "card", "visa", "mastercard", "amex", "auth", "change", "cash", "tender", "amt", "balance",
        "payment", "paid", "refund", "save", "saving", "discount", "rewards", "points", "coupon",
        "sold by", "return", "eligible", "delivered", "track", "buy it again", "view", "feedback", "review",
        "order #", "order placed", "invoice", "thank you", "phone", "tel",
    ]

    // MARK: Lines

    /// A piece of recognized text with its corners, as Vision gives them
    /// (0–1 of the image, origin at the bottom left).
    struct TextBox {
        var text: String
        var topLeft: CGPoint
        var topRight: CGPoint
        var bottomLeft: CGPoint
        var bottomRight: CGPoint
    }

    /// Joins text pieces into lines, left to right. The photo's tilt is
    /// measured from the pieces and undone first, so a slightly crooked
    /// receipt still puts each price on its label's line. Buttons and
    /// payment pieces are dropped before joining. `aspect` is the image's
    /// width ÷ height.
    static func lines(from boxes: [TextBox], aspect: Double) -> [String] {
        func scaled(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }
        let kept = boxes.filter { box in
            let lower = box.text.lowercased()
            return !pieceNoise.contains { lower.hasPrefix($0) || lower == $0 }
        }
        struct Piece { let text: String; let x: Double; let right: Double; let y: Double; let height: Double }
        func center(_ box: TextBox) -> CGPoint {
            let c = [box.topLeft, box.topRight, box.bottomLeft, box.bottomRight].map(scaled)
            return CGPoint(x: c.map(\.x).reduce(0, +) / 4, y: c.map(\.y).reduce(0, +) / 4)
        }
        func pieces(tilt: Double) -> [Piece] {
            let (sinA, cosA) = (sin(-tilt), cos(-tilt))
            return kept.map { box -> Piece in
                let c = center(box)
                let left = (scaled(box.topLeft).x + scaled(box.bottomLeft).x) / 2
                let right = (scaled(box.topRight).x + scaled(box.bottomRight).x) / 2
                let height = hypot(scaled(box.topLeft).x - scaled(box.bottomLeft).x,
                                   scaled(box.topLeft).y - scaled(box.bottomLeft).y)
                return Piece(text: box.text, x: left * cosA - c.y * sinA, right: right * cosA - c.y * sinA,
                             y: c.x * sinA + c.y * cosA, height: max(height, 0.001))
            }.sorted { $0.y > $1.y }
        }
        func group(_ pieces: [Piece]) -> [[Piece]] {
            var rows: [[Piece]] = []
            for piece in pieces {
                // Pieces on one line never overlap side to side; if they
                // would, they're from neighboring lines (a wide page at the
                // wrong tilt).
                if let row = rows.last, let first = row.first,
                   abs(first.y - piece.y) < min(first.height, piece.height) * 0.55,
                   !row.contains(where: { min($0.right, piece.right) - max($0.x, piece.x) > 0.25 * piece.height }) {
                    rows[rows.count - 1].append(piece)
                } else {
                    rows.append([piece])
                }
            }
            return rows
        }

        // The photo's tilt: the angle that lines the most pieces up into
        // shared rows (Vision's own boxes are mostly level, so they can't say).
        var best = (tilt: 0.0, score: -1)
        for step in -24...24 {
            let tilt = Double(step) * 0.25 * .pi / 180
            let score = group(pieces(tilt: tilt)).reduce(0) { $0 + $1.count * $1.count }
            if score > best.score || (score == best.score && abs(tilt) < abs(best.tilt)) { best = (tilt, score) }
        }
        let rows = group(pieces(tilt: best.tilt))
        return rows.map { $0.sorted { $0.x < $1.x }.map(\.text).joined(separator: "  ") }
    }

    /// Whole text pieces that are buttons or links on an order page.
    private static let pieceNoise = [
        "leave seller feedback", "write a product review", "buy it again", "view your item", "track package",
        "get product support", "return or replace items", "view invoice", "view related transactions",
        "sold by", "archive order",
    ]

    // MARK: Parsing

    static func parse(_ rawLines: [String]) -> Receipt {
        let lines = rawLines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var receipt = Receipt()

        // Summary amounts: each label takes the first amount after it on its
        // line ("SUB-TOTAL:$ 15.96  TAX: 1.56" has two), or the next line's
        // when its own has none. First of each wins.
        for (i, line) in lines.enumerated() {
            for (kind, amount) in labeledAmounts(line, next: i + 1 < lines.count ? lines[i + 1] : nil) {
                switch kind {
                case .subtotal: receipt.subtotal = receipt.subtotal ?? amount
                case .tax: receipt.tax = receipt.tax ?? amount
                case .shipping: receipt.shipping = receipt.shipping ?? amount
                case .total: receipt.total = receipt.total ?? amount
                case .ignore: break
                }
            }
        }

        let firstSummary = lines.firstIndex { label(of: $0).map { $0 != .ignore } ?? false } ?? lines.count
        func isNoise(_ index: Int) -> Bool {
            let lower = lines[index].lowercased()
            return noise.contains { lower.contains($0) }
        }
        func candidates(_ range: Range<Int>) -> [Int] {
            range.filter { index in
                guard label(of: lines[index]) == nil, !isNoise(index) else { return false }
                // A wrapped noise line ("Return or replace items: Eligible" /
                // "through November 14, 2026"): its second half has no price.
                if index > 0, isNoise(index - 1), amounts(in: lines[index]).isEmpty { return false }
                return !isDate(lines[index]) || !amounts(in: lines[index]).isEmpty
            }
        }
        // A register lists items before the totals; an order page may list
        // them after (fall back to the rest when nothing's above).
        let above = candidates(0..<firstSummary)
        let itemLines = above.contains { !amounts(in: lines[$0]).isEmpty } ? above : candidates(0..<lines.count)
        var pending: (sku: String?, quantity: Int, each: Double?)?
        var previousName: String?
        for index in itemLines {
            let line = lines[index]
            if let code = registerCode(line) {
                pending = code
                continue
            }
            let prices = amounts(in: line)
            let name = cleanName(line)
            // Quantity from the code line, or worked out from its price each
            // (the quantity is easy to miss when the photo is soft).
            var quantity = pending?.quantity ?? 1
            if let each = pending?.each, each > 0, let total = prices.last {
                let ratio = total / each
                if ratio >= 1.5, abs(ratio - ratio.rounded()) < 0.01 { quantity = Int(ratio.rounded()) }
            }
            if prices.isEmpty {
                // A product name with its price on a later line (order pages):
                // the nearest one above (wrapped notes and dates are skipped).
                if name.count >= 6, name.contains(where: \.isLetter) { previousName = name }
                continue
            }
            let lineTotal = prices.last!
            guard lineTotal > 0 else { continue }
            let itemName: String
            if name.count >= 3, name.contains(where: \.isLetter) {
                itemName = name
            } else if let previous = previousName {
                itemName = previous
            } else {
                continue
            }
            if quantity == 1, let pack = packCount(itemName) { quantity = pack }
            receipt.items.append(Item(name: itemName, partNumber: pending?.sku, quantity: quantity,
                                      lineTotal: lineTotal))
            pending = nil
            previousName = nil
        }

        // On an order page the item price can repeat the subtotal row; keep
        // items only if they don't overshoot the subtotal.
        if let subtotal = receipt.subtotal, receipt.itemsTotal > subtotal + 0.015 {
            receipt.items = trimmed(receipt.items, to: subtotal)
        }
        return receipt
    }

    /// Labels on a line and the amount each one labels.
    private static func labeledAmounts(_ line: String, next: String?) -> [(Label, Double)] {
        let lower = line.lowercased()
        let keywords: [(String, Label)] = [
            ("total before tax", .ignore), ("subtotal", .subtotal), ("sub-total", .subtotal), ("sub total", .subtotal),
            ("estimated tax", .tax), ("tax", .tax), ("shipping", .shipping), ("handling", .shipping),
            ("grand total", .total), ("order total", .total), ("total", .total),
        ]
        // Each keyword's position, skipping ones inside a longer keyword already found.
        var found: [(start: String.Index, end: String.Index, label: Label)] = []
        for (word, label) in keywords {
            var searchStart = lower.startIndex
            while let range = lower.range(of: word, range: searchStart..<lower.endIndex) {
                if !found.contains(where: { $0.start <= range.lowerBound && range.upperBound <= $0.end }) {
                    found.append((range.lowerBound, range.upperBound, label))
                }
                searchStart = range.upperBound
            }
        }
        found.sort { $0.start < $1.start }
        var result: [(Label, Double)] = []
        for (n, item) in found.enumerated() {
            let segmentEnd = n + 1 < found.count ? found[n + 1].start : lower.endIndex
            let segment = String(line[item.end..<segmentEnd])
            if let amount = amounts(in: segment).first {
                result.append((item.label, amount))
            } else if n == found.count - 1, let next, label(of: next) == nil, let amount = amounts(in: next).first {
                result.append((item.label, amount))
            }
        }
        return result
    }

    /// A register's code line: "1004892  1 EA  $12.99 EA" or "502  3 EA  ,99 EA"
    /// (SKU, quantity, price each) with the name on the next line.
    /// Read loosely, since photos add stray marks ("1004892/ EA EA $12.99 EA"):
    /// once its prices are taken out, the line holds only numbers, "EA" or
    /// "@", and punctuation.
    static func registerCode(_ line: String) -> (sku: String?, quantity: Int, each: Double?)? {
        let prices = amounts(in: line)
        var rest = line
        if let regex = try? NSRegularExpression(pattern: amountPattern) {
            rest = regex.stringByReplacingMatches(in: rest, range: NSRange(rest.startIndex..., in: rest), withTemplate: " ")
        }
        let words = rest.uppercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "@" }
            .map(String.init)
        guard words.contains(where: { $0 == "EA" || $0 == "@" }),
              words.allSatisfy({ $0 == "EA" || $0 == "@" || $0 == "X" || $0.allSatisfy(\.isNumber) }) else { return nil }
        let numbers = words.filter { $0.allSatisfy(\.isNumber) }
        let sku = numbers.first { $0.count >= 3 }
        let quantity = numbers.first { $0.count <= 3 && $0 != sku }.flatMap { Int($0) } ?? 1
        return (sku, max(1, quantity), prices.last)
    }

    /// "Brake Fluid Dot 3 (Pack Of 2)", "2-Pack", "4 pk", "Set of 4" → the count.
    static func packCount(_ name: String) -> Int? {
        let patterns = [#"pack\s+of\s+(\d{1,2})"#, #"set\s+of\s+(\d{1,2})"#, #"(\d{1,2})\s*-?\s*(?:pack|pk)\b"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                  let range = Range(match.range(at: 1), in: name), let count = Int(name[range]), count >= 2 else { continue }
            return count
        }
        return nil
    }

    /// "through November 14, 2026", "10/20/26", "Oct 15".
    static func isDate(_ line: String) -> Bool {
        let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september",
                      "october", "november", "december", "jan ", "feb ", "mar ", "apr ", "jun ", "jul ", "aug ",
                      "sep ", "sept ", "oct ", "nov ", "dec "]
        let lower = line.lowercased()
        if months.contains(where: lower.contains) && lower.contains(where: \.isNumber) { return true }
        return lower.range(of: #"\b\d{1,2}/\d{1,2}/\d{2,4}\b"#, options: .regularExpression) != nil
    }

    /// The line without its prices and stray symbols: "11 OZ BLASTER PENETRATING SPR".
    static func cleanName(_ line: String) -> String {
        var name = line
        if let regex = try? NSRegularExpression(pattern: amountPattern) {
            name = regex.stringByReplacingMatches(in: name, range: NSRange(name.startIndex..., in: name), withTemplate: "")
        }
        name = name.replacingOccurrences(of: "$", with: "")
        // Names cut short on an order page: "Genuine Honda And Acura Brak…".
        while name.hasSuffix("…") || name.hasSuffix(".") { name.removeLast() }
        return name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -:*"))
    }

    /// The first items whose prices add up to the subtotal, if any do.
    private static func trimmed(_ items: [Item], to subtotal: Double) -> [Item] {
        var sum = 0.0
        for (i, item) in items.enumerated() {
            sum += item.lineTotal
            if abs(sum - subtotal) <= 0.015 { return Array(items.prefix(i + 1)) }
        }
        return items
    }
}

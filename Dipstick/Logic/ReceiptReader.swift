//
//  ReceiptReader.swift
//  Dipstick
//

import Foundation
import CoreGraphics
import ImageIO
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads a receipt photo or an order screenshot: Apple's on-device text
/// recognition, then `ReceiptParser`'s rules. If those don't add up and the
/// phone has Apple's on-device language model (iOS 26+), the model reads the
/// same text, and its answer is used only if it adds up. Nothing leaves the
/// phone.
nonisolated enum ReceiptReader {
    struct Result {
        let receipt: ReceiptParser.Receipt
        /// The lines read, for tuning.
        let lines: [String]
        let usedModel: Bool
    }

    static func read(_ image: CGImage, orientation: CGImagePropertyOrientation = .up) async -> Result {
        let lines = recognizedLines(image, orientation: orientation)
        let parsed = ReceiptParser.parse(lines)
        if parsed.checks { return Result(receipt: parsed, lines: lines, usedModel: false) }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *), let modelRead = await ModelReader.read(lines), modelRead.checks {
            return Result(receipt: modelRead, lines: lines, usedModel: true)
        }
        #endif
        return Result(receipt: parsed, lines: lines, usedModel: false)
    }

    static func recognizedLines(_ image: CGImage, orientation: CGImagePropertyOrientation) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try? VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
        let boxes = (request.results ?? []).compactMap { observation -> ReceiptParser.TextBox? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return .init(text: text, topLeft: observation.topLeft, topRight: observation.topRight,
                         bottomLeft: observation.bottomLeft, bottomRight: observation.bottomRight)
        }
        let sideways = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
        let (w, h) = (Double(image.width), Double(image.height))
        return ReceiptParser.lines(from: boxes, aspect: sideways ? h / w : w / h)
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
private enum ModelReader {
    @Generable(description: "A store receipt or online order")
    struct Receipt {
        @Guide(description: "Every product bought, in order. Not subtotal, tax, shipping, total, payment or card lines.")
        var items: [Item]
        @Guide(description: "Subtotal before tax, if printed")
        var subtotal: Double?
        @Guide(description: "Sales tax, if printed")
        var tax: Double?
        @Guide(description: "Shipping or handling, if printed")
        var shipping: Double?
        @Guide(description: "Grand total paid")
        var total: Double?
    }

    @Generable
    struct Item {
        @Guide(description: "Product name as printed")
        var name: String
        @Guide(description: "SKU or part number printed on the product's own line or the line just above it; empty if none. Never an order number.")
        var partNumber: String?
        @Guide(description: "Quantity bought; 1 if not shown")
        var quantity: Int
        @Guide(description: "Price for this line: quantity times the price each")
        var lineTotal: Double
    }

    static func read(_ lines: [String]) async -> ReceiptParser.Receipt? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: """
            You read text recognized from a receipt photo or an online order page and list what was bought. \
            Use only numbers that appear in the text; a comma in a price like 15,96 is a decimal point. \
            The items' line totals must add up to the subtotal.
            """)
        guard let response = try? await session.respond(to: "Receipt text:\n" + lines.joined(separator: "\n"),
                                                        generating: Receipt.self) else { return nil }
        let r = response.content
        return ReceiptParser.Receipt(
            items: r.items.map {
                .init(name: $0.name, partNumber: ($0.partNumber?.isEmpty ?? true) ? nil : $0.partNumber,
                      quantity: max(1, $0.quantity), lineTotal: $0.lineTotal)
            },
            subtotal: r.subtotal, tax: r.tax, shipping: r.shipping, total: r.total
        )
    }
}
#endif

// MARK: - Splitting a receipt

/// The parts for a job from a receipt: the chosen items, each with its share
/// of the tax (and shipping, if included) in proportion to its price, so
/// unrelated items bought on the same trip don't inflate the job.
nonisolated enum ReceiptSplit {
    struct Part: Equatable {
        var name: String
        var partNumber: String?
        var quantity: Int
        /// What the receipt charged for this line, before tax.
        var itemTotal: Double
        /// What this line cost including its share of tax (and shipping).
        var total: Double
        /// The receipt's price each, before tax.
        var priceEach: Double { itemTotal / Double(max(quantity, 1)) }
        /// This line's share of the tax (and shipping).
        var taxShare: Double { total - itemTotal }
    }

    static func parts(of receipt: ReceiptParser.Receipt, chosen: Set<UUID>, includeShipping: Bool) -> [Part] {
        let items = receipt.items.filter { chosen.contains($0.id) }
        let base = receipt.subtotal ?? receipt.itemsTotal
        guard base > 0 else {
            return items.map { Part(name: $0.name, partNumber: $0.partNumber, quantity: $0.quantity,
                                    itemTotal: $0.lineTotal, total: $0.lineTotal) }
        }
        let extra = (receipt.tax ?? 0) + (includeShipping ? (receipt.shipping ?? 0) : 0)
        // Shares to the cent, with leftover cents to the largest remainders,
        // so the parts add up to exactly the chosen items' part of the bill.
        let exact = items.map { $0.lineTotal * extra / base }
        var cents = exact.map { Int(($0 * 100).rounded(.down)) }
        let target = Int((exact.reduce(0, +) * 100).rounded())
        let order = exact.indices.sorted { (exact[$0] * 100).truncatingRemainder(dividingBy: 1) > (exact[$1] * 100).truncatingRemainder(dividingBy: 1) }
        for index in order.prefix(max(0, target - cents.reduce(0, +))) { cents[index] += 1 }
        return zip(items, cents).map { item, share in
            Part(name: item.name, partNumber: item.partNumber, quantity: item.quantity, itemTotal: item.lineTotal,
                 total: ((item.lineTotal + Double(share) / 100) * 100).rounded() / 100)
        }
    }
}

//
//  RecordReader.swift
//  Dipstick
//

import Foundation
import CoreGraphics
import ImageIO
import PDFKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads service records from photos, screenshots and PDFs, all on the
/// phone: Apple's text recognition (or the PDF's own text), then Apple's
/// on-device language model to pick out each visit. Every value it finds is
/// then checked against the page text (`RecordImport.check`). Without the
/// language model, `RecordImport.visitsByRules` reads simpler layouts.
nonisolated enum RecordReader {
    /// One photo or PDF page: its text, and a picture to look back at.
    struct Page: Sendable {
        var text: String
        var preview: Data?
    }

    // MARK: Pages

    static func page(fromImage data: Data) -> Page? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32)
            .flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
        let lines = ReceiptReader.recognizedLines(image, orientation: orientation)
        return Page(text: lines.joined(separator: "\n"), preview: PhotoStore.downsized(data, maxPixels: 2_400))
    }

    /// Each page's own text; pages that are only a scan are read like photos.
    static func pages(fromPDF url: URL) -> [Page] {
        guard let document = PDFDocument(url: url) else { return [] }
        return (0..<document.pageCount).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let jpeg = render(page)
            let text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 {
                return Page(text: text, preview: jpeg)
            }
            guard let jpeg, var scanned = self.page(fromImage: jpeg) else { return nil }
            scanned.preview = jpeg
            return scanned
        }
    }

    static func render(_ page: PDFPage) -> Data? {
        #if canImport(UIKit)
        return page.thumbnail(of: CGSize(width: 2_000, height: 2_000), for: .mediaBox).jpegData(compressionQuality: 0.8)
        #else
        let image = page.thumbnail(of: CGSize(width: 2_000, height: 2_000), for: .mediaBox)
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        #endif
    }

    /// A page for the schedule reader: its text pieces with positions
    /// (for grid tables), its text, and a picture.
    static func schedulePage(fromImage data: Data) -> ScheduleReader.Page? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32)
            .flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
        let textBoxes = ReceiptReader.recognizedBoxes(image, orientation: orientation)
        let sideways = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
        let (w, h) = (Double(image.width), Double(image.height))
        let lines = ReceiptParser.lines(from: textBoxes, aspect: sideways ? h / w : w / h)
        return ScheduleReader.Page(boxes: ScheduleReader.boxes(from: textBoxes), text: lines.joined(separator: "\n"),
                                   preview: PhotoStore.downsized(data, maxPixels: 2_400),
                                   ink: ScheduleReader.InkMap(imageData: data))
    }

    /// PDF pages for the schedule reader, each rendered and read like a photo
    /// (grids need positions), keeping the PDF's own text when it has some.
    /// A whole owner's manual can be hundreds of pages, so only the pages
    /// whose text looks like the maintenance schedule are read (see
    /// `ScheduleReader.schedulePageIndexes`). A scanned PDF with no text is
    /// read up to `ScheduleReader.maxScannedPages` pages.
    static func schedulePages(fromPDF url: URL) -> [ScheduleReader.Page] {
        guard let document = PDFDocument(url: url) else { return [] }
        let texts = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        return ScheduleReader.schedulePageIndexes(texts).compactMap { index in
            guard let page = document.page(at: index), let jpeg = render(page),
                  var read = schedulePage(fromImage: jpeg) else { return nil }
            if let text = page.string, text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 40 { read.text = text }
            return read
        }
    }

    // MARK: Reading

    struct Result {
        var visits: [RecordImport.Visit]
        var usedModel: Bool
    }

    /// Reads every page. `progress` gets (pieces done, pieces in all).
    static func read(_ pages: [Page], known: [String],
                     progress: @escaping @Sendable (Int, Int) async -> Void = { _, _ in }) async -> Result {
        // Lists are read one visit at a time so no service lands on the wrong visit.
        let pieces = pages.enumerated().flatMap { index, page in
            (RecordImport.visitBlocks(page.text) ?? chunks(page.text)).map { (index, $0) }
        }
        var visits: [RecordImport.Visit] = []
        var usedModel = false
        for (n, (index, text)) in pieces.enumerated() {
            await progress(n, pieces.count)
            var found: [RecordImport.Visit]? = nil
            #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                found = await ModelReader.read(text, page: index, known: known)
                if found != nil { usedModel = true }
            }
            #endif
            // Check the model's services against the text it read.
            if var visits = found {
                for i in visits.indices { RecordImport.reconcile(&visits[i], source: text, known: known) }
                found = visits
            }
            let lines = text.components(separatedBy: .newlines)
            var pageVisits = found ?? RecordImport.visitsByRules(lines: lines, page: index, known: known)
            let grounding = RecordImport.Grounding(pages[index].text)
            for i in pageVisits.indices {
                RecordImport.mergeRepeats(&pageVisits[i])
                RecordImport.check(&pageVisits[i], against: grounding)
                RecordImport.fillMissingMileage(&pageVisits[i], pageText: pages[index].text)
            }
            // A visit with neither its date nor its mileage on the page was made up.
            pageVisits.removeAll(where: RecordImport.isUnfounded)
            visits += pageVisits
        }
        await progress(pieces.count, pieces.count)
        return Result(visits: RecordImport.tidy(visits), usedModel: usedModel)
    }

    /// Splits long text at line breaks so each piece fits the on-device
    /// model with room for its answer.
    static func chunks(_ text: String, limit: Int = 2_800) -> [String] {
        var pieces: [String] = []
        var current = ""
        for line in text.components(separatedBy: .newlines) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            if current.count + line.count + 1 > limit, !current.isEmpty {
                pieces.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n") + String(line.prefix(limit))
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    // MARK: Turning text answers into values

    /// "18,967 mi" → 18967. nil if there are no digits.
    static func wholeNumber(_ text: String) -> Int? {
        let digits = text.prefix { !$0.isLetter || $0 == "," }.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    /// "$1,234.56" → 1234.56. nil if it isn't an amount.
    static func amount(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let match = cleaned.firstMatch(of: #/^-?\d+(?:\.\d+)?/#) else { return nil }
        return Double(match.output)
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
private enum ModelReader {
    @Generable(description: "Car service records")
    struct Found {
        @Guide(description: "Each service visit, in the order they appear in the text")
        var visits: [FoundVisit]
    }

    @Generable
    struct FoundVisit {
        @Guide(description: "Date of the visit, copied exactly as written")
        var date: String
        @Guide(description: "The car's odometer mileage at the visit, copied exactly as written; empty if not in the text")
        var mileage: String
        @Guide(description: "Shop or dealer name; empty if not in the text")
        var shop: String
        @Guide(description: "Invoice, repair order or work order number; empty if not in the text")
        var invoice: String
        @Guide(description: "Total paid for the whole visit, copied exactly as written; empty if not in the text")
        var total: String
        @Guide(description: "Each service or repair done at this visit")
        var services: [FoundService]
    }

    @Generable
    struct FoundService {
        @Guide(description: "Short name of the service")
        var name: String
        @Guide(description: "Price charged for this service, copied exactly as written; empty if not in the text")
        var price: String
        @Guide(description: "Parts used, with part numbers if shown")
        var parts: [FoundPart]
        @Guide(description: "Findings or measurements worth keeping, in a few words; empty if none")
        var notes: String
    }

    @Generable
    struct FoundPart {
        @Guide(description: "Part name")
        var name: String
        @Guide(description: "Part number; empty if not shown")
        var partNumber: String
        @Guide(description: "How many; 1 if not shown")
        var quantity: Int
        @Guide(description: "Price for this line, copied as written; empty if not shown")
        var price: String
    }

    static func read(_ text: String, page: Int, known: [String], depth: Int = 0) async -> [RecordImport.Visit]? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let names = Array(Set(known.map { $0 }).prefix(30)).joined(separator: ", ")
        let session = LanguageModelSession(instructions: """
            You read text recognized from car service records: shop invoices, repair orders, vehicle history \
            reports or handwritten logs. List every service visit. A visit is one date at one shop; list each \
            service or repair done at it separately.
            Copy dates, mileage and prices exactly as they appear. Never guess or calculate a number; leave it \
            empty if it isn't in the text.
            Mileage is the car's odometer reading (often labeled Mileage, Odometer or Miles In). Never use part \
            numbers, invoice numbers, phone numbers, ZIP codes or VINs as mileage.
            Every line of work done is its own service, even when a report lists several under one date; \
            don't put work done in the notes.
            Leave out recommended or declined work, coupons and ads.
            Name services briefly. Use one of these names when it fits: \(names).
            """)
        do {
            let response = try await session.respond(to: "Text:\n" + text, generating: Found.self,
                                                     options: GenerationOptions(samplingMode: .greedy))
            return response.content.visits.compactMap { visit(from: $0, page: page, known: known) }
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize where depth < 2 {
            // Too long with its answer: read each half on its own.
            let lines = text.components(separatedBy: .newlines)
            let half = lines.count / 2
            guard half > 0 else { return nil }
            let first = await read(lines[..<half].joined(separator: "\n"), page: page, known: known, depth: depth + 1)
            let second = await read(lines[half...].joined(separator: "\n"), page: page, known: known, depth: depth + 1)
            guard first != nil || second != nil else { return nil }
            return (first ?? []) + (second ?? [])
        } catch {
            #if DEBUG
            print("RecordReader: language model failed: \(error)")
            #endif
            return nil
        }
    }

    private static func visit(from found: FoundVisit, page: Int, known: [String]) -> RecordImport.Visit? {
        let services = found.services.flatMap { s -> [RecordImport.Service] in
            let name = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return [] }
            let parts = s.parts.compactMap { p -> RecordCSV.Part? in
                let partName = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !partName.isEmpty else { return nil }
                let quantity = max(1, p.quantity)
                let each = RecordReader.amount(p.price).map { $0 / Double(quantity) } ?? 0
                return RecordCSV.Part(name: partName, cost: each,
                                      partNumber: p.partNumber.isEmpty ? nil : p.partNumber, quantity: quantity)
            }
            let notes = s.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            return RecordImport.services(raw: name, price: RecordReader.amount(s.price), parts: parts,
                                         notes: notes.isEmpty ? nil : notes, known: known)
        }
        guard !services.isEmpty else { return nil }
        let shop = found.shop.trimmingCharacters(in: .whitespacesAndNewlines)
        // An invoice number has a digit in it.
        let invoice = found.invoice.contains(where: \.isNumber) ? found.invoice.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return RecordImport.Visit(date: FlexibleDate.parse(found.date), odometer: RecordReader.wholeNumber(found.mileage),
                                  shop: shop.isEmpty ? nil : shop, invoice: invoice.isEmpty ? nil : invoice,
                                  total: RecordReader.amount(found.total), services: services, page: page)
    }
}
#endif

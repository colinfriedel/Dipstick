//
//  RecordImport.swift
//  Dipstick
//

import Foundation

/// Service records found in photos, screenshots, PDFs or spreadsheets, before
/// they're imported. A *visit* is one trip to the shop (one date, one
/// mileage); it becomes one logged service per service done.
///
/// Nothing found is trusted blindly: every date, mileage and price is checked
/// against the text actually on the page (`Grounding`), mileage is checked
/// for going backwards, and records already in the log are marked. Anything
/// doubtful is flagged for you to check before importing.
nonisolated enum RecordImport {
    struct Visit: Identifiable, Equatable {
        var id = UUID()
        var date: Date?
        var odometer: Int?
        var shop: String?
        var invoice: String?
        /// What the whole visit cost, if shown.
        var total: Double?
        var services: [Service] = []
        /// Which page or photo it came from (0-based).
        var page = 0
        /// Values that weren't found on the page or don't fit with the
        /// other visits.
        var unsure: Set<Field> = []
        var include = true

        enum Field: Hashable { case date, odometer, total }

        var includedServices: [Service] { services.filter(\.include) }
        /// A date and a mileage are needed to import.
        var isComplete: Bool { date != nil && odometer != nil }
    }

    struct Service: Identifiable, Equatable {
        var id = UUID()
        var name: String
        var price: Double?
        var parts: [RecordCSV.Part] = []
        var notes: String?
        var priceUnsure = false
        /// The name isn't backed up by the page's text.
        var nameUnsure = false
        /// Already in the log; left out unless ticked.
        var isDuplicate = false
        var include = true
    }

    // MARK: Service names

    /// Common ways shops write a service, mapped to the app's names. The
    /// first match wins, so specific ones come first.
    private static let nameRules: [(name: String, any: [String])] = [
        ("Cabin air filter", ["cabin air filter", "cabin filter", "pollen filter"]),
        ("Brake fluid", ["brake fluid", "brake flush", "brake system flush", "bleed brake", "brake bleed"]),
        ("Transmission fluid", ["transmission fluid", "transmission flush", "trans fluid", "transmission service",
                                "atf", "cvt fluid"]),
        ("Power steering fluid", ["power steering"]),
        ("Differential fluid", ["differential"]),
        ("Coolant", ["coolant", "antifreeze", "radiator flush", "cooling system"]),
        ("Oil change", ["oil change", "oil & filter", "oil and filter", "oil/filter", "lube oil", "lube, oil",
                        "oil filter", "engine oil", "synthetic oil", "lof", "oil service"]),
        ("Tire rotation", ["rotate", "rotation"]),
        ("Alignment", ["alignment"]),
        ("Brake pads", ["brake pad", "brake job", "pads and rotors", "rotors", "brake shoes"]),
        ("Air filter", ["engine air filter", "air filter", "air cleaner"]),
        ("Spark plugs", ["spark plug"]),
        ("Timing belt", ["timing belt"]),
        ("Drive belt", ["serpentine", "drive belt", "accessory belt"]),
        ("Wiper blades", ["wiper"]),
        ("Battery", ["battery replace", "new battery", "replace battery", "battery install"]),
        ("Tires", ["new tires", "new tire", "tire replacement", "replace tires", "tires replaced", "tire replaced",
                   "tires installed", "mount and balance", "mount & balance"]),
        ("Smog check", ["smog", "emissions inspection", "emission inspection", "emissions test", "emission test"]),
        ("Inspection", ["multi-point", "multipoint", "inspection"]),
    ]

    /// The app's name for a service as a shop wrote it, using this car's
    /// spelling when it already has that service.
    static func serviceName(_ raw: String, known: [String] = []) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let lower = " " + cleaned.lowercased() + " "
        let words = Set(lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let matched = nameRules.first { rule in
            rule.any.contains { key in
                // Short keys ("lof", "atf") must be whole words.
                key.count <= 3 ? words.contains(key) : lower.contains(key)
            }
        }?.name
        let name = matched ?? sentenceCase(trimmingWorkWords(cleaned))
        return known.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
    }

    /// Every service named in one line of work, in the order written:
    /// "Replace engine oil and filter, rotate tires" → Oil change, Tire
    /// rotation. A line naming none is one service, named as written.
    static func serviceNames(in raw: String, known: [String] = []) -> [String] {
        let lower = " " + raw.lowercased() + " "
        let words = Set(lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        var hits: [(range: Range<String.Index>, name: String)] = []
        for rule in nameRules {
            for key in rule.any {
                guard key.count > 3 || words.contains(key), let r = lower.range(of: key) else { continue }
                hits.append((r, rule.name))
            }
        }
        // Longest matches first; a shorter one inside it ("inspection" in
        // "emissions inspection") is the same service.
        var kept: [(range: Range<String.Index>, name: String)] = []
        for hit in hits.sorted(by: { lower.distance(from: $0.range.lowerBound, to: $0.range.upperBound)
                                     > lower.distance(from: $1.range.lowerBound, to: $1.range.upperBound) })
        where !kept.contains(where: { $0.range.overlaps(hit.range) }) {
            kept.append(hit)
        }
        var names: [String] = []
        for hit in kept.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) where !names.contains(hit.name) {
            names.append(hit.name)
        }
        guard !names.isEmpty else { return [serviceName(raw, known: known)] }
        return names.map { name in known.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name }
    }

    /// Work that was only recommended or declined, not done.
    static func isNotDone(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["declin", "recommend", "not performed", "customer refused", "deferred"].contains { lower.contains($0) }
    }

    /// Services from one line of work as a shop or report wrote it: split
    /// when it names several, the price, parts and notes going with the
    /// first. Work named in the notes ("Brake fluid flushed") becomes its own
    /// service. Nothing for declined or recommended work.
    static func services(raw: String, price: Double?, parts: [RecordCSV.Part], notes: String?,
                         known: [String] = []) -> [Service] {
        guard !isNotDone(raw), !isNotDone(notes ?? "") else { return [] }
        var names = serviceNames(in: raw, known: known)
        var keptNotes: [String] = []
        for piece in (notes ?? "").components(separatedBy: CharacterSet(charactersIn: ".;\n")) {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let found = serviceNames(in: trimmed, known: known).filter { name in
                nameRules.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            }
            if ["n/a", "na", "none", "-"].contains(trimmed.lowercased()) { continue }
            if found.isEmpty || isNotDone(trimmed) {
                keptNotes.append(trimmed)
            } else {
                for name in found where !names.contains(name) { names.append(name) }
            }
        }
        var seenParts = Set<String>()
        // Only parts the page actually lists (with a number or a price), not
        // ones made up from the service's name.
        let uniqueParts = parts.map { part -> RecordCSV.Part in
                // A "part number" that's just the name again isn't one.
                var part = part
                if let number = part.partNumber,
                   !number.contains(where: \.isNumber) || part.name.lowercased().contains(number.lowercased())
                    || number.lowercased() == "n/a" {
                    part.partNumber = nil
                }
                return part
            }
            .filter { $0.partNumber != nil || $0.cost > 0 }
            // The same part listed again without its number.
            .filter { part in
                part.partNumber != nil || !parts.contains {
                    $0.partNumber != nil && $0.name.caseInsensitiveCompare(part.name) == .orderedSame
                }
            }
            .filter { seenParts.insert("\($0.name.lowercased())|\($0.partNumber ?? "")").inserted }
            .map { var p = $0; p.name = sentenceCase(p.name); return p }
        let note = keptNotes.joined(separator: "; ")
        return names.enumerated().map { i, name in
            i == 0 ? Service(name: name, price: price, parts: uniqueParts,
                             notes: note.isEmpty ? nil : sentenceCase(note))
                   : Service(name: name)
        }
    }

    /// Checks the language model's services against the text they came
    /// from:
    /// - a package name ("20K service") is replaced by the services its
    ///   line on the page names (Oil change, Tire rotation);
    /// - a service the text doesn't mention is swapped for services the
    ///   text does name that weren't listed, or else marked to check;
    /// - services the text clearly names but the reader missed are added.
    static func reconcile(_ visit: inout Visit, source: String, known: [String] = []) {
        let lines = source.components(separatedBy: .newlines)
        let lower = source.lowercased()
        func ruleNames(_ text: String) -> [String] {
            isNotDone(text) ? [] : serviceNames(in: text, known: known).filter(isRuleName)
        }
        let named = lines.flatMap(ruleNames)
        var result: [Service] = []
        var unsupported: [Service] = []
        for service in visit.services {
            if isRuleName(service.name) {
                if named.contains(where: { $0.caseInsensitiveCompare(service.name) == .orderedSame }) {
                    result.append(service)
                } else {
                    unsupported.append(service)
                }
                continue
            }
            // A name of its own: expand it from its line if that line names services.
            let key = service.name.lowercased()
            if let line = lines.first(where: { $0.lowercased().contains(key) && !isNotDone($0) }) {
                let expanded = ruleNames(line)
                if !expanded.isEmpty {
                    for (i, name) in expanded.enumerated() {
                        var s = i == 0 ? service : Service(name: name)
                        s.name = name
                        if i == 0 { s.notes = [service.name, service.notes].compactMap { $0 }.joined(separator: "; ") }
                        result.append(s)
                    }
                    continue
                }
            }
            var s = service
            let words = key.split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 4 }
            s.nameUnsure = !words.isEmpty && words.filter { lower.contains($0) }.count * 2 < words.count
            result.append(s)
        }
        let listed = Set(result.map { $0.name.lowercased() })
        var missing = named.filter { !listed.contains($0.lowercased()) }
        missing = missing.enumerated().filter { i, name in !missing[..<i].contains(name) }.map(\.element)
        // Services the reader got wrong become the ones the text names.
        for (i, wrong) in unsupported.enumerated() {
            if i < missing.count {
                var s = wrong
                s.name = missing[i]
                result.append(s)
            } else {
                var s = wrong
                s.nameUnsure = true
                result.append(s)
            }
        }
        for name in missing.dropFirst(unsupported.count) { result.append(Service(name: name)) }

        // Parts must be on the page too: their number, and most of their name.
        let compact = lower.filter { !$0.isWhitespace }
        for i in result.indices {
            result[i].parts = result[i].parts.compactMap { part in
                var part = part
                if let number = part.partNumber {
                    if number.contains(where: \.isWhitespace) {
                        // Part numbers have no spaces: that's the part's name.
                        part.name = sentenceCase(number)
                        part.partNumber = nil
                    } else if !compact.contains(number.lowercased()) {
                        part.partNumber = nil
                    } else if let line = lines.first(where: { $0.lowercased().contains(number.lowercased()) }),
                              let name = nameAfter(number, in: line) {
                        // The page's own name for that number.
                        part.name = name
                        return part
                    }
                }
                let words = part.name.lowercased().split(whereSeparator: { !$0.isLetter }).filter { $0.count >= 4 }
                guard words.allSatisfy({ lower.contains($0) }) else { return nil }
                return part.partNumber != nil || part.cost > 0 ? part : nil
            }
        }
        visit.services = result
        mergeRepeats(&visit)
    }

    /// "PARTS: 15400-PLM-A02 OIL FILTER 1 @ 7.50" → "Oil filter" for 15400-PLM-A02.
    private static func nameAfter(_ number: String, in line: String) -> String? {
        guard let range = line.range(of: number, options: .caseInsensitive) else { return nil }
        let words = line[range.upperBound...].split(separator: " ")
            .prefix { word in word.contains(where: \.isLetter) && word != "@" }
        let name = words.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        return name.count >= 3 ? sentenceCase(name) : nil
    }

    private static func isRuleName(_ name: String) -> Bool {
        nameRules.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Mileage for a visit the reader left without one: a number on the
    /// same line as the visit's date, as in a history table
    /// ("06/10/2017   17,162   Clear Blue"). Marked to check.
    static func fillMissingMileage(_ visit: inout Visit, pageText: String) {
        guard visit.odometer == nil, let date = visit.date else { return }
        let key = FlexibleDate.key(date)
        for line in pageText.components(separatedBy: .newlines)
        where FlexibleDate.all(in: line).contains(where: { FlexibleDate.key($0) == key }) {
            if let value = odometer(in: [line]) ?? bareMileage(in: line) {
                visit.odometer = value
                visit.unsure.insert(.odometer)
                return
            }
        }
    }

    /// A number that looks like mileage on a line that also has a date:
    /// with a thousands comma, or 4 to 6 digits that aren't the year.
    private static func bareMileage(in line: String) -> Int? {
        var text = line
        for m in line.matches(of: #/\b\d{1,4}[-\/.]\d{1,2}[-\/.]\d{2,4}\b/#).reversed() { text.removeSubrange(m.range) }
        for m in text.matches(of: #/(?:^|[^\d.$])(\d{1,3},\d{3}|\d{4,6})(?![\d.])/#) {
            guard let value = Int(m.output.1.replacingOccurrences(of: ",", with: "")) else { continue }
            if m.output.1.contains(",") || !(1950...2100).contains(value) { return value }
        }
        return nil
    }

    /// Services named twice in one visit become one.
    static func mergeRepeats(_ visit: inout Visit) {
        var merged: [Service] = []
        for service in visit.services {
            if let i = merged.firstIndex(where: { $0.name.caseInsensitiveCompare(service.name) == .orderedSame }) {
                merged[i].price = merged[i].price ?? service.price
                merged[i].parts += service.parts
                merged[i].notes = [merged[i].notes, service.notes].compactMap { $0 }.joined(separator: "; ").nilIfEmpty
            } else {
                merged.append(service)
            }
        }
        visit.services = merged
    }

    /// "Heater blower transistor replaced" → "Heater blower transistor".
    private static func trimmingWorkWords(_ text: String) -> String {
        var result = text
        for suffix in [" replaced", " performed", " changed", " completed", " done", " serviced", " installed"]
        where result.lowercased().hasSuffix(suffix) && result.count > suffix.count + 3 {
            result = String(result.dropLast(suffix.count))
        }
        for prefix in ["replace ", "replaced ", "install ", "installed ", "r&r ", "r & r "]
        where result.lowercased().hasPrefix(prefix) && result.count > prefix.count + 3 {
            result = String(result.dropFirst(prefix.count))
        }
        return result.prefix(1).uppercased() + result.dropFirst()
    }

    /// "REPLACE WIPER BLADES" → "Replace wiper blades"; mixed case is kept.
    private static func sentenceCase(_ text: String) -> String {
        guard text == text.uppercased() else { return text }
        let lower = text.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }

    // MARK: Checking against the page

    /// The dates, whole numbers and amounts that appear in a page's text.
    struct Grounding {
        let numbers: Set<Int>
        let amounts: Set<Int>     // in cents
        let dates: Set<String>    // yyyy-MM-dd

        init(_ text: String) {
            var numbers = Set<Int>()
            var amounts = Set<Int>()
            // Numbers with optional thousands commas and decimals: 18,967 / 249.95 / $1,234.56
            let pattern = #/\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?/#
            for match in text.matches(of: pattern) {
                let plain = match.output.replacingOccurrences(of: ",", with: "")
                if let whole = Int(plain) { numbers.insert(whole) }
                if let value = Double(plain) { amounts.insert(Int((value * 100).rounded())) }
            }
            self.numbers = numbers
            self.amounts = amounts
            dates = Set(FlexibleDate.all(in: text).map(FlexibleDate.key))
        }

        func has(number: Int) -> Bool { numbers.contains(number) }
        func has(amount: Double) -> Bool { amounts.contains(Int((amount * 100).rounded())) }
        func has(date: Date) -> Bool { dates.contains(FlexibleDate.key(date)) }
    }

    /// Marks values not found in the page text.
    static func check(_ visit: inout Visit, against grounding: Grounding) {
        if let date = visit.date, !grounding.has(date: date) { visit.unsure.insert(.date) }
        if visit.date == nil { visit.unsure.insert(.date) }
        if let odometer = visit.odometer, !grounding.has(number: odometer) { visit.unsure.insert(.odometer) }
        if visit.odometer == nil { visit.unsure.insert(.odometer) }
        if let total = visit.total, !grounding.has(amount: total) { visit.unsure.insert(.total) }
        for i in visit.services.indices {
            if let price = visit.services[i].price, !grounding.has(amount: price) {
                visit.services[i].priceUnsure = true
            }
        }
    }

    /// Neither the date nor the mileage is on the page: the reader made the
    /// visit up rather than read it.
    static func isUnfounded(_ visit: Visit) -> Bool {
        visit.unsure.contains(.date) && (visit.odometer == nil || visit.unsure.contains(.odometer))
    }

    /// Combines visits found twice (overlapping pages, or a visit split
    /// across pages): same day and the same or a missing mileage. Then sorts
    /// by date and marks mileage that goes backwards.
    static func tidy(_ visits: [Visit], calendar: Calendar = .current) -> [Visit] {
        var merged: [Visit] = []
        for visit in visits {
            if let i = merged.firstIndex(where: { other in
                guard let a = other.date, let b = visit.date, calendar.isDate(a, inSameDayAs: b) else { return false }
                return other.odometer == nil || visit.odometer == nil || other.odometer == visit.odometer
            }) {
                var into = merged[i]
                into.odometer = into.odometer ?? visit.odometer
                into.shop = into.shop ?? visit.shop
                into.invoice = into.invoice ?? visit.invoice
                into.total = into.total ?? visit.total
                for service in visit.services where !into.services.contains(where: {
                    $0.name.caseInsensitiveCompare(service.name) == .orderedSame
                }) {
                    into.services.append(service)
                }
                // A value found on either page counts.
                into.unsure.formIntersection(visit.unsure)
                merged[i] = into
            } else {
                merged.append(visit)
            }
        }
        merged.sort { ($0.date ?? .distantFuture, $0.odometer ?? 0) < ($1.date ?? .distantFuture, $1.odometer ?? 0) }

        // Mileage should rise with the date. Flag the readings that disagree
        // with the most others first, so one typo doesn't flag its neighbors.
        var remaining = merged.indices.filter { merged[$0].date != nil && merged[$0].odometer != nil }
        func conflict(_ i: Int, _ j: Int) -> Bool {
            let (a, b) = (merged[i], merged[j])
            guard !calendar.isDate(a.date!, inSameDayAs: b.date!) else { return false }
            return (a.date! < b.date!) != (a.odometer! <= b.odometer!)
        }
        while true {
            let counts = remaining.map { i in remaining.filter { conflict(i, $0) }.count }
            guard let most = counts.max(), most > 0 else { break }
            let worst = remaining.indices.filter { counts[$0] == most }.map { remaining[$0] }
            for i in worst { merged[i].unsure.insert(.odometer) }
            // Two readings that only disagree with each other: can't tell which, so both are flagged.
            remaining.removeAll { worst.contains($0) }
        }
        return merged
    }

    /// Marks services already in the log: the same service within a day.
    static func markDuplicates(_ visits: inout [Visit], existing: [(date: Date, type: String)],
                               calendar: Calendar = .current) {
        for v in visits.indices {
            guard let date = visits[v].date else { continue }
            for s in visits[v].services.indices {
                let name = visits[v].services[s].name
                let found = existing.contains { item in
                    item.type.caseInsensitiveCompare(name) == .orderedSame
                        && abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: item.date),
                                                       to: calendar.startOfDay(for: date)).day ?? 99) <= 1
                }
                visits[v].services[s].isDuplicate = found
                if found { visits[v].services[s].include = false }
            }
        }
    }

    // MARK: To logged services

    /// One logged service per included service. Prices are kept; anything
    /// the visit total adds on top (tax, fees) is shared among the priced
    /// services. With only a visit total, it goes on the first service and
    /// the others say it's included there.
    static func rows(for visit: Visit) -> [RecordCSV.ServiceRow] {
        guard visit.include, let date = visit.date, let odometer = visit.odometer else { return [] }
        let services = visit.includedServices
        guard !services.isEmpty else { return [] }

        let visitNotes = [visit.shop, visit.invoice.map { "invoice \($0)" }].compactMap { $0 }
        let priced = services.filter { ($0.price ?? 0) > 0 }
        var costs = services.map { $0.price ?? 0 }
        var extraNotes = Array(repeating: [String](), count: services.count)

        if priced.isEmpty, let total = visit.total, total > 0 {
            costs[0] = total
            if services.count > 1 {
                extraNotes[0].append("whole-visit total, also covers " + services.dropFirst().map(\.name).joined(separator: ", "))
                for i in 1..<services.count { extraNotes[i].append("cost included in \(services[0].name)") }
            }
        } else if let total = visit.total, services.count == visit.services.count {
            let base = priced.reduce(0) { $0 + ($1.price ?? 0) }
            let extraCents = Int(((total - base) * 100).rounded())
            if extraCents > 0, base > 0 {
                let indices = services.indices.filter { (services[$0].price ?? 0) > 0 }
                let exact = indices.map { Double(extraCents) * (services[$0].price ?? 0) / base }
                var cents = exact.map { Int($0.rounded(.down)) }
                let order = exact.indices.sorted { exact[$0] - Double(cents[$0]) > exact[$1] - Double(cents[$1]) }
                for k in order.prefix(extraCents - cents.reduce(0, +)) { cents[k] += 1 }
                for (k, i) in indices.enumerated() where cents[k] > 0 {
                    costs[i] = ((costs[i] * 100).rounded() + Double(cents[k])) / 100
                    extraNotes[i].append("includes \(Units.currency(Double(cents[k]) / 100)) tax and fees")
                }
            }
        }

        return services.indices.map { i in
            let notes = (visitNotes + [services[i].notes].compactMap { $0 } + extraNotes[i])
                .filter { !$0.isEmpty }.joined(separator: "; ")
            return RecordCSV.ServiceRow(date: date, odometer: odometer, serviceType: services[i].name, cost: costs[i],
                                        parts: services[i].parts, nextDueOdometer: nil, nextDueDate: nil,
                                        notes: notes.isEmpty ? nil : notes)
        }
    }

    // MARK: Reading without the language model

    /// A simple reader for when the phone has no on-device language model:
    /// a page with one date is one visit (an invoice); a page with several
    /// dates is a list, one visit per date. Services are recognized from the
    /// usual names.
    static func visitsByRules(lines: [String], page: Int, known: [String] = []) -> [Visit] {
        let dated = lines.indices.filter { !FlexibleDate.all(in: lines[$0]).isEmpty }
        guard !dated.isEmpty else { return [] }
        let blocks: [Range<Int>]
        if Set(dated.compactMap { FlexibleDate.all(in: lines[$0]).first.map(FlexibleDate.key) }).count == 1 {
            blocks = [0..<lines.count]
        } else {
            blocks = dated.enumerated().map { n, start in start..<(n + 1 < dated.count ? dated[n + 1] : lines.count) }
        }
        return blocks.compactMap { block in
            let text = lines[block]
            var visit = Visit(page: page)
            visit.date = text.lazy.compactMap { FlexibleDate.all(in: $0).first }.first
            visit.odometer = odometer(in: Array(text))
            if visit.odometer == nil, let dated = text.first(where: { !FlexibleDate.all(in: $0).isEmpty }) {
                visit.odometer = bareMileage(in: dated)
            }
            visit.total = total(in: Array(text))
            var seen = Set<String>()
            for line in text where !isNotDone(line) {
                for name in serviceNames(in: line, known: known)
                where nameRules.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
                    && seen.insert(name.lowercased()).inserted {
                    visit.services.append(Service(name: name))
                }
            }
            return visit.services.isEmpty ? nil : visit
        }
    }

    /// A list of visits (a history report or a log) split into one piece
    /// per visit, each starting at a line that begins with a date, with the
    /// column headings above the first one repeated on each. nil for a page
    /// that isn't a list (an invoice, where dates appear after labels).
    static func visitBlocks(_ text: String) -> [String]? {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let starts = lines.indices.filter { i in
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            guard let first = FlexibleDate.all(in: String(line.prefix(20))).first else { return false }
            // The date must be at the start of the line, not after a label.
            let lead = line.prefix(20).prefix { !$0.isNumber && !$0.isLetter }
            return lead.isEmpty && (line.first?.isNumber == true || FlexibleDate.all(in: String(line.prefix(12))).first == first)
        }
        let distinct = Set(starts.compactMap { FlexibleDate.all(in: lines[$0]).first.map(FlexibleDate.key) })
        guard starts.count >= 2, distinct.count >= 2 else { return nil }
        let heading = lines[..<starts[0]].suffix(3).joined(separator: "\n")
        return starts.enumerated().map { n, start in
            let end = n + 1 < starts.count ? starts[n + 1] : lines.count
            let block = lines[start..<end].joined(separator: "\n")
            return heading.isEmpty ? block : heading + "\n" + block
        }
    }

    /// Mileage: a number labeled odometer/mileage/miles, or followed by "mi".
    static func odometer(in lines: [String]) -> Int? {
        let labeled = #/(?i)(?:odometer|odo|mileage|miles in|mileage in|miles)\D{0,12}(\d{1,3}(?:,\d{3})+|\d{3,7})/#
        let suffixed = #/(?i)(\d{1,3}(?:,\d{3})+|\d{3,7})\s*(?:mi\b|miles\b)/#
        for line in lines {
            if let m = line.firstMatch(of: labeled) ?? line.firstMatch(of: suffixed),
               let value = Int(m.output.1.replacingOccurrences(of: ",", with: "")) {
                return value
            }
        }
        return nil
    }

    /// The visit total: an amount on a "total" / "amount due" line.
    static func total(in lines: [String]) -> Double? {
        let pattern = #/(?i)(?:grand total|invoice total|total due|amount due|balance due|total)\D{0,20}\$?\s*(\d{1,3}(?:,\d{3})*\.\d{2})/#
        for line in lines.reversed() where !line.lowercased().contains("subtotal") {
            if let m = line.firstMatch(of: pattern) {
                return Double(m.output.1.replacingOccurrences(of: ",", with: ""))
            }
        }
        return nil
    }

    // MARK: Spreadsheets

    /// Reads a spreadsheet in any layout by its column names (date, mileage,
    /// service or description, cost, notes, shop). nil if it doesn't have at
    /// least a date and a service column.
    static func visits(fromCSV text: String, known: [String] = []) -> [Visit]? {
        var rows = CSV.parse(text)
        guard !rows.isEmpty else { return nil }
        let header = rows.removeFirst().map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func column(_ names: [String]) -> Int? {
            header.firstIndex { h in names.contains(h) } ?? header.firstIndex { h in names.contains { h.contains($0) } }
        }
        guard let dateCol = column(["date", "service date", "date of service"]),
              let serviceCol = column(["service", "description", "work performed", "work", "item", "task", "type", "job"])
        else { return nil }
        let odoCol = column(["odometer", "mileage", "miles", "odo"])
        let costCol = column(["cost", "price", "amount", "total", "paid"])
        let notesCol = column(["notes", "comments", "comment", "details"])
        let shopCol = column(["shop", "vendor", "location", "dealer", "garage", "where"])

        var visits: [Visit] = []
        for (n, fields) in rows.enumerated() {
            func value(_ i: Int?) -> String {
                guard let i, i < fields.count else { return "" }
                return fields[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let serviceText = value(serviceCol)
            guard !serviceText.isEmpty else { continue }
            let date = FlexibleDate.all(in: value(dateCol)).first
            let odometer = Units.parseWholeNumber(value(odoCol).replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "mi", with: "").trimmingCharacters(in: .whitespaces))
            let price = Units.parseDecimal(value(costCol).replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: ",", with: ""))
            let service = Service(name: serviceName(serviceText, known: known), price: price,
                                  notes: value(notesCol).isEmpty ? nil : value(notesCol))
            if let i = visits.firstIndex(where: { $0.date != nil && $0.date == date && $0.odometer == odometer }) {
                visits[i].services.append(service)
            } else {
                var visit = Visit(date: date, odometer: odometer, shop: value(shopCol).isEmpty ? nil : value(shopCol),
                                  services: [service], page: n)
                if date == nil { visit.unsure.insert(.date) }
                if odometer == nil { visit.unsure.insert(.odometer) }
                visits.append(visit)
            }
        }
        return visits
    }
}

// MARK: - Dates as people write them

/// Reads the many ways dates are written on invoices and reports:
/// 2017-08-08, 8/8/2017, 08/08/17, 8-8-2017, 8.8.2017, Aug 8, 2017,
/// August 8 2017, 8 Aug 2017, 08-AUG-17. Numeric dates are read US style
/// (month first) unless the first number can't be a month.
nonisolated enum FlexibleDate {
    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    static func key(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Every date in the text, in order.
    static func all(in text: String) -> [Date] {
        var found: [(Range<String.Index>, Date)] = []
        let iso = #/\b(\d{4})[-\/.](\d{1,2})[-\/.](\d{1,2})\b/#
        let numeric = #/\b(\d{1,2})[-\/.](\d{1,2})[-\/.](\d{4}|\d{2})\b/#
        let monthFirst = #/(?i)\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})\b/#
        let dayFirst = #/(?i)\b(\d{1,2})[\s-]+(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?[\s-]+(\d{4}|\d{2})\b/#

        for m in text.matches(of: iso) {
            if let d = make(Int(m.output.1), Int(m.output.2), Int(m.output.3)) { found.append((m.range, d)) }
        }
        for m in text.matches(of: numeric) where !found.contains(where: { $0.0.overlaps(m.range) }) {
            guard let a = Int(m.output.1), let b = Int(m.output.2), let y = year(String(m.output.3)) else { continue }
            let (month, day) = a > 12 ? (b, a) : (a, b)
            if let d = make(y, month, day) { found.append((m.range, d)) }
        }
        for m in text.matches(of: monthFirst) {
            if let d = make(Int(m.output.3), month(String(m.output.1)), Int(m.output.2)) { found.append((m.range, d)) }
        }
        for m in text.matches(of: dayFirst) where !found.contains(where: { $0.0.overlaps(m.range) }) {
            if let d = make(year(String(m.output.3)), month(String(m.output.2)), Int(m.output.1)) { found.append((m.range, d)) }
        }
        return found.sorted { $0.0.lowerBound < $1.0.lowerBound }.map(\.1)
    }

    static func parse(_ text: String) -> Date? { all(in: text).first }

    private static func month(_ name: String) -> Int? {
        months.firstIndex(of: String(name.lowercased().prefix(3))).map { $0 + 1 }
    }

    private static func year(_ text: String) -> Int? {
        guard let y = Int(text) else { return nil }
        if text.count == 2 { return y < 70 ? 2000 + y : 1900 + y }
        return y
    }

    private static func make(_ year: Int?, _ month: Int?, _ day: Int?) -> Date? {
        guard let year, let month, let day, (1950...2100).contains(year), (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }
}

nonisolated private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

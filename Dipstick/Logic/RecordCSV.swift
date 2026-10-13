//
//  RecordCSV.swift
//  Dipstick
//

import Foundation
import SwiftData

/// Converts one vehicle's fuel and service records to and from the CSV format
/// described in docs/csv-format.md. Works on plain row values so it can be
/// tested without SwiftData; the Vehicle extension at the bottom bridges to the
/// models.
enum RecordCSV {
    static let columns = [
        "type", "date", "odometer", "gallons", "total_cost", "full_tank", "station",
        "service", "parts", "next_due_odometer", "next_due_date", "notes",
    ]

    struct FuelRow: Equatable {
        var date: Date
        var odometer: Int
        var gallons: Double
        /// 0 = unknown.
        var totalCost: Double
        var isFullTank: Bool
        var station: String?
        var notes: String?
    }

    struct Part: Equatable {
        var name: String
        var cost: Double
    }

    struct ServiceRow: Equatable {
        var date: Date
        var odometer: Int
        var serviceType: String
        var cost: Double
        var parts: [Part]
        var nextDueOdometer: Int?
        var nextDueDate: Date?
        var notes: String?
    }

    struct Problem: Equatable {
        /// 1-based row number in the file, counting the header as row 1.
        let row: Int
        let message: String
    }

    struct Parsed {
        var fuel: [FuelRow] = []
        var services: [ServiceRow] = []
        var problems: [Problem] = []
    }

    // MARK: Writing

    static func encode(fuel: [FuelRow], services: [ServiceRow], calendar: Calendar = .current) -> String {
        var lines = [CSV.line(columns)]
        let fuelLines = fuel.sorted { $0.odometer < $1.odometer }.map { row in
            CSV.line([
                "fuel", format(row.date, calendar), String(row.odometer),
                number(row.gallons, decimals: 3), row.totalCost > 0 ? number(row.totalCost, decimals: 2) : "",
                row.isFullTank ? "yes" : "no", row.station ?? "",
                "", "", "", "", row.notes ?? "",
            ])
        }
        let serviceLines = services.sorted { ($0.date, $0.odometer) < ($1.date, $1.odometer) }.map { row in
            CSV.line([
                "service", format(row.date, calendar), String(row.odometer),
                "", row.cost > 0 ? number(row.cost, decimals: 2) : "", "", "",
                row.serviceType,
                partsText(row.parts),
                row.nextDueOdometer.map(String.init) ?? "",
                row.nextDueDate.map { format($0, calendar) } ?? "",
                row.notes ?? "",
            ])
        }
        lines += fuelLines + serviceLines
        return lines.joined(separator: "\n") + "\n"
    }

    private static func partsText(_ parts: [Part]) -> String {
        let items: [String] = parts.map { part in
            part.cost > 0 ? part.name + "=" + number(part.cost, decimals: 2) : part.name
        }
        return items.joined(separator: "; ")
    }

    // MARK: Reading

    static func decode(_ text: String, calendar: Calendar = .current) -> Parsed {
        var result = Parsed()
        var rows = CSV.parse(text)
        guard !rows.isEmpty else {
            result.problems.append(Problem(row: 1, message: "The file is empty."))
            return result
        }

        // Map columns by header name so column order doesn't matter.
        let header = rows.removeFirst().map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        var index: [String: Int] = [:]
        for (i, name) in header.enumerated() { index[name] = i }
        let missing = ["type", "date", "odometer"].filter { index[$0] == nil }
        guard missing.isEmpty else {
            result.problems.append(Problem(
                row: 1,
                message: "Missing column\(missing.count == 1 ? "" : "s"): \(missing.joined(separator: ", ")). Is this a Dipstick CSV?"
            ))
            return result
        }

        for (offset, fields) in rows.enumerated() {
            let rowNumber = offset + 2
            func value(_ column: String) -> String {
                guard let i = index[column], i < fields.count else { return "" }
                return fields[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            func problem(_ message: String) {
                result.problems.append(Problem(row: rowNumber, message: message))
            }

            guard let date = parseDate(value("date"), calendar) else {
                problem("Date \"\(value("date"))\" isn't YYYY-MM-DD.")
                continue
            }
            guard let odometer = Units.parseWholeNumber(value("odometer")), odometer >= 0 else {
                problem("Odometer \"\(value("odometer"))\" isn't a whole number.")
                continue
            }
            let costText = value("total_cost")
            let cost: Double
            if costText.isEmpty {
                cost = 0
            } else if let parsed = Units.parseDecimal(costText), parsed >= 0 {
                cost = parsed
            } else {
                problem("Cost \"\(costText)\" isn't a number.")
                continue
            }
            let notes = value("notes").nilIfEmpty

            switch value("type").lowercased() {
            case "fuel":
                guard let gallons = Units.parseDecimal(value("gallons")), gallons > 0 else {
                    problem("Fuel row needs gallons greater than 0.")
                    continue
                }
                let fullText = value("full_tank").lowercased()
                guard ["", "yes", "no", "y", "n", "true", "false"].contains(fullText) else {
                    problem("full_tank should be yes or no, not \"\(value("full_tank"))\".")
                    continue
                }
                result.fuel.append(FuelRow(
                    date: date, odometer: odometer, gallons: gallons, totalCost: cost,
                    isFullTank: !["no", "n", "false"].contains(fullText),
                    station: value("station").nilIfEmpty, notes: notes
                ))

            case "service":
                guard let serviceType = value("service").nilIfEmpty else {
                    problem("Service row needs a service name.")
                    continue
                }
                guard let parts = parseParts(value("parts")) else {
                    problem("Parts \"\(value("parts"))\" should look like \"Oil filter=9.99; Drain plug gasket\".")
                    continue
                }
                let dueOdometerText = value("next_due_odometer")
                let dueOdometer = Units.parseWholeNumber(dueOdometerText)
                if !dueOdometerText.isEmpty && dueOdometer == nil {
                    problem("next_due_odometer \"\(dueOdometerText)\" isn't a whole number.")
                    continue
                }
                let dueDateText = value("next_due_date")
                let dueDate = parseDate(dueDateText, calendar)
                if !dueDateText.isEmpty && dueDate == nil {
                    problem("next_due_date \"\(dueDateText)\" isn't YYYY-MM-DD.")
                    continue
                }
                result.services.append(ServiceRow(
                    date: date, odometer: odometer, serviceType: serviceType, cost: cost, parts: parts,
                    nextDueOdometer: dueOdometer, nextDueDate: dueDate, notes: notes
                ))

            default:
                problem("Type should be fuel or service, not \"\(value("type"))\".")
            }
        }
        return result
    }

    // MARK: Duplicates

    /// Splits parsed rows into new ones and ones already in the log (or repeated
    /// earlier in the same file). Fuel matches on odometer (the app allows one
    /// fill-up per reading); services on date + odometer + service name.
    static func newRows(
        _ parsed: Parsed,
        existingFuelOdometers: Set<Int>,
        existingServiceKeys: Set<String>,
        calendar: Calendar = .current
    ) -> (fuel: [FuelRow], services: [ServiceRow], duplicates: Int) {
        var fuelSeen = existingFuelOdometers
        var serviceSeen = existingServiceKeys
        var duplicates = 0

        let fuel = parsed.fuel.filter { row in
            if fuelSeen.insert(row.odometer).inserted { return true }
            duplicates += 1
            return false
        }
        let services = parsed.services.filter { row in
            let key = serviceKey(date: row.date, odometer: row.odometer, type: row.serviceType, calendar: calendar)
            if serviceSeen.insert(key).inserted { return true }
            duplicates += 1
            return false
        }
        return (fuel, services, duplicates)
    }

    static func serviceKey(date: Date, odometer: Int, type: String, calendar: Calendar = .current) -> String {
        "\(format(date, calendar))|\(odometer)|\(type.lowercased())"
    }

    // MARK: Helpers

    private static func formatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false
        return formatter
    }

    static func format(_ date: Date, _ calendar: Calendar) -> String {
        let formatter = formatter(calendar)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// YYYY-MM-DD, plus M/D/YYYY and M/D/YY since that's how dates are often
    /// written by hand.
    static func parseDate(_ text: String, _ calendar: Calendar) -> Date? {
        let formatter = formatter(calendar)
        if text.contains("-") {
            formatter.dateFormat = "yyyy-MM-dd"
        } else {
            // Pick by the year's length: "M/d/yyyy" would read "8/31/26" as the year 26 AD.
            let year = text.split(separator: "/").last ?? ""
            formatter.dateFormat = year.count == 2 ? "M/d/yy" : "M/d/yyyy"
        }
        return formatter.date(from: text)
    }

    private static func number(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// "Oil filter=9.99; Drain plug gasket" → parts. nil if a cost isn't a number.
    private static func parseParts(_ text: String) -> [Part]? {
        var parts: [Part] = []
        for item in text.split(separator: ";") {
            let pieces = item.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard let name = pieces.first, !name.isEmpty else { continue }
            var cost = 0.0
            if pieces.count == 2, !pieces[1].isEmpty {
                guard let parsed = Units.parseDecimal(pieces[1]), parsed >= 0 else { return nil }
                cost = parsed
            }
            parts.append(Part(name: name, cost: cost))
        }
        return parts
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Vehicle bridge

extension Vehicle {
    func exportCSV() -> String {
        RecordCSV.encode(
            fuel: (fuelEntries ?? []).map {
                .init(date: $0.date, odometer: $0.odometer, gallons: $0.gallons, totalCost: $0.totalCost,
                      isFullTank: $0.isFullTank, station: $0.station, notes: $0.notes)
            },
            services: (maintenanceEntries ?? []).map {
                .init(date: $0.date, odometer: $0.odometer, serviceType: $0.serviceType, cost: $0.cost,
                      parts: $0.sortedParts.map { .init(name: $0.name, cost: $0.cost) },
                      nextDueOdometer: $0.nextDueOdometer, nextDueDate: $0.nextDueDate, notes: $0.notes)
            }
        )
    }

    /// Rows from `parsed` that aren't already in this vehicle's log.
    func importPlan(for parsed: RecordCSV.Parsed) -> (fuel: [RecordCSV.FuelRow], services: [RecordCSV.ServiceRow], duplicates: Int) {
        RecordCSV.newRows(
            parsed,
            existingFuelOdometers: Set((fuelEntries ?? []).map(\.odometer)),
            existingServiceKeys: Set((maintenanceEntries ?? []).map {
                RecordCSV.serviceKey(date: $0.date, odometer: $0.odometer, type: $0.serviceType)
            })
        )
    }

    func importRecords(fuel: [RecordCSV.FuelRow], services: [RecordCSV.ServiceRow], into context: ModelContext) {
        for row in fuel {
            let entry = FuelEntry(
                date: row.date, odometer: row.odometer, gallons: row.gallons, totalCost: row.totalCost,
                isFullTank: row.isFullTank, station: row.station, notes: row.notes
            )
            context.insert(entry)
            entry.vehicle = self
        }
        for row in services {
            let entry = MaintenanceEntry(
                date: row.date, odometer: row.odometer, serviceType: row.serviceType, cost: row.cost,
                notes: row.notes, nextDueOdometer: row.nextDueOdometer, nextDueDate: row.nextDueDate
            )
            context.insert(entry)
            entry.vehicle = self
            for part in row.parts {
                let model = PartUsed(name: part.name, cost: part.cost)
                context.insert(model)
                model.entry = entry
            }
        }
        let highest = (fuel.map(\.odometer) + services.map(\.odometer)).max()
        if let highest { recordOdometer(highest) }
    }
}

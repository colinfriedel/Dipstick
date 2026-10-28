//
//  CSV.swift
//  Dipstick
//

import Foundation

/// Minimal CSV reading and writing (RFC 4180): comma-separated, fields may be
/// wrapped in double quotes, `""` is a literal quote, quoted fields may contain
/// commas and line breaks.
nonisolated enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        chars.append("\n")  // flush the last row
        var i = 0

        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n", "\r\n", "\r":  // Swift treats "\r\n" as one Character
                    row.append(field)
                    field = ""
                    if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty) {
                        rows.append(row)
                    }
                    row = []
                default:
                    field.append(c)
                }
            }
            i += 1
        }
        return rows
    }

    /// Quotes a field only when it needs it.
    static func escape(_ field: String) -> String {
        if field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    static func line(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }
}

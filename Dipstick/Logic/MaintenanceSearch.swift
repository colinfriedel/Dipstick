//
//  MaintenanceSearch.swift
//  Dipstick
//

import Foundation

/// Search and filter rules for the maintenance history.
enum MaintenanceSearch {
    /// True if the record matches the service-type filter (nil = all types)
    /// and every word of the query appears in its type, notes or part names.
    static func matches(
        serviceType: String,
        notes: String?,
        partNames: [String],
        query: String,
        typeFilter: String?
    ) -> Bool {
        if let typeFilter, serviceType.caseInsensitiveCompare(typeFilter) != .orderedSame {
            return false
        }
        let haystack = ([serviceType, notes ?? ""] + partNames).joined(separator: " ")
        return query
            .split(whereSeparator: \.isWhitespace)
            .allSatisfy { haystack.localizedStandardContains($0) }
    }
}

extension MaintenanceEntry {
    func matches(query: String, typeFilter: String?) -> Bool {
        MaintenanceSearch.matches(
            serviceType: serviceType,
            notes: notes,
            partNames: (parts ?? []).map(\.name),
            query: query,
            typeFilter: typeFilter
        )
    }
}

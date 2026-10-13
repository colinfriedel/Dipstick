//
//  ServiceType.swift
//  Dipstick
//

import Foundation

/// The built-in service names offered in pickers. Add new ones here.
enum ServiceType {
    static let builtIn = [
        "Oil change",
        "Tire rotation",
        "Brake pads",
        "Air filter",
        "Cabin air filter",
        "Spark plugs",
        "Coolant",
        "Transmission fluid",
        "Brake fluid",
        "Fluids",
        "Battery",
        "Wiper blades",
        "Inspection",
    ]

    /// Built-in names followed by any custom names already used, so a custom
    /// service only has to be typed once.
    static func options<S: Sequence>(addingUsed used: S) -> [String] where S.Element == String {
        let builtInKeys = Set(builtIn.map { $0.lowercased() })
        var seen = Set<String>()
        let custom = used
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !builtInKeys.contains($0.lowercased()) }
            .filter { seen.insert($0.lowercased()).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return builtIn + custom
    }
}

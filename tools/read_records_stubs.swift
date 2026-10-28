// Stand-ins for app types the record reader uses, so it builds as a Mac
// tool without SwiftData or SwiftUI (see read_records.swift).

import Foundation

enum RecordCSV {
    struct Part: Equatable {
        var name: String
        var cost: Double
        var partNumber: String? = nil
        var quantity: Int = 1
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
}

enum PhotoStore {
    static func downsized(_ data: Data, maxPixels: Int = 2_000) -> Data? { data }
}

enum ServiceTypeList {
    static let builtIn = ["Oil change", "Tire rotation", "Brake pads", "Air filter", "Cabin air filter", "Spark plugs",
                          "Coolant", "Transmission fluid", "Brake fluid", "Fluids", "Battery", "Wiper blades", "Inspection"]
}

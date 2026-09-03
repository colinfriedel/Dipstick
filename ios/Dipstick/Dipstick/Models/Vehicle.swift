import Foundation

/// One vehicle, mirroring vehicle-service's JSON. The backend uses camelCase keys
/// (`currentOdometer`), which match these property names exactly, so `Codable`
/// needs no custom `CodingKeys`.
struct Vehicle: Identifiable, Codable, Hashable {
    let id: Int
    var name: String
    var year: Int?
    var make: String?
    var model: String?
    var vin: String?
    var currentOdometer: Int
}

extension Vehicle {
    /// "2018 Honda Civic" — the descriptive parts that are actually set. Empty
    /// string when none are.
    var descriptiveTitle: String {
        [year.map(String.init), make, model]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// The request body for creating or updating a vehicle. Mirrors the backend's
/// `VehicleInput`: no `id` (the server assigns it). `nil` optionals are omitted
/// from the JSON by `Codable`'s synthesized encoder, which the backend reads as
/// "not set" / SQL NULL.
struct VehicleInput: Codable {
    var name: String
    var year: Int?
    var make: String?
    var model: String?
    var vin: String?
    var currentOdometer: Int
}

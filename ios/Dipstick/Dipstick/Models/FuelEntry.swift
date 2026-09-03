import Foundation

/// One logged fuel stop, mirroring activity-service's JSON. `costPerGallon` and
/// `mpg` are computed by the backend; `mpg` is nil for partial fill-ups and for
/// the first full tank in a vehicle's history.
struct FuelEntry: Identifiable, Codable, Hashable {
    let id: Int
    let vehicleId: Int
    var date: CalendarDate
    var odometer: Int
    var gallons: Double
    var totalCost: Double
    var isFullTank: Bool
    var stationName: String?
    var notes: String?
    var costPerGallon: Double
    var mpg: Double?
}

/// Request body for `POST /vehicles/{id}/fuel-entries`. The client sends either
/// `totalCost` or `pricePerGallon`; the backend derives the other.
struct FuelEntryInput: Codable {
    var date: CalendarDate
    var odometer: Int
    var gallons: Double
    var totalCost: Double?
    var pricePerGallon: Double?
    var isFullTank: Bool
    var stationName: String?
    var notes: String?
}

import Foundation

/// One line item under a maintenance entry.
struct Part: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var cost: Double

    enum CodingKeys: String, CodingKey { case name, cost }
}

/// One logged service, mirroring activity-service's JSON.
struct MaintenanceEntry: Identifiable, Codable, Hashable {
    let id: Int
    let vehicleId: Int
    var date: CalendarDate
    var odometer: Int
    var serviceType: String
    var cost: Double
    var partsUsed: [Part]?
    var notes: String?
    var nextDueOdometer: Int?
    var nextDueDate: CalendarDate?
}

/// Request body for `POST /vehicles/{id}/maintenance-entries`.
struct MaintenanceEntryInput: Codable {
    var date: CalendarDate
    var odometer: Int
    var serviceType: String
    var cost: Double
    var partsUsed: [Part]?
    var notes: String?
    var nextDueOdometer: Int?
    var nextDueDate: CalendarDate?
}

/// The service types the form offers as quick picks. "Other" lets the user type
/// a custom string, matching the backend's free-text `service_type`.
enum ServiceType {
    static let common = [
        "Oil change",
        "Tire rotation",
        "Brake pads",
        "Air filter",
        "Cabin filter",
        "Fluid change",
        "Spark plugs",
        "Battery",
    ]
}

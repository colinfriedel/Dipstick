import Foundation

/// One (vehicle, service type) that needs attention, from `GET /due`.
struct DueItem: Codable, Hashable, Identifiable {
    enum Status: String, Codable {
        case dueSoon = "due_soon"
        case overdue

        var label: String {
            switch self {
            case .dueSoon: "Due soon"
            case .overdue: "Overdue"
            }
        }
    }

    let vehicleId: Int
    let serviceType: String
    let status: Status
    let milesRemaining: Int?
    let daysRemaining: Int?
    let nextDueOdometer: Int?
    let nextDueDate: CalendarDate?
    let lastServiceOdometer: Int
    let lastServiceDate: CalendarDate

    var id: String { "\(vehicleId)-\(serviceType)" }
}

/// The `GET /due` response envelope. `warnings` is present only when the result
/// is degraded (e.g. vehicle-service was unreachable so mileage checks were skipped).
struct DueResponse: Codable {
    let items: [DueItem]
    let generatedAt: String
    let warnings: [String]?
}

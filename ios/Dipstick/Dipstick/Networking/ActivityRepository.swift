import Foundation

/// What the fuel/maintenance/due screens need from activity-service. Protocol so
/// view models test and preview against an in-memory fake.
protocol ActivityRepository {
    func fuelEntries(vehicleID: Int) async throws -> [FuelEntry]
    func createFuelEntry(vehicleID: Int, _ input: FuelEntryInput) async throws -> FuelEntry

    func maintenanceEntries(vehicleID: Int) async throws -> [MaintenanceEntry]
    func createMaintenanceEntry(vehicleID: Int, _ input: MaintenanceEntryInput) async throws -> MaintenanceEntry

    func due() async throws -> DueResponse
}

/// The real implementation, talking to activity-service over HTTP.
struct APIActivityRepository: ActivityRepository {
    let client: APIClient

    func fuelEntries(vehicleID: Int) async throws -> [FuelEntry] {
        try await client.get("vehicles/\(vehicleID)/fuel-entries")
    }

    func createFuelEntry(vehicleID: Int, _ input: FuelEntryInput) async throws -> FuelEntry {
        try await client.post("vehicles/\(vehicleID)/fuel-entries", body: input)
    }

    func maintenanceEntries(vehicleID: Int) async throws -> [MaintenanceEntry] {
        try await client.get("vehicles/\(vehicleID)/maintenance-entries")
    }

    func createMaintenanceEntry(vehicleID: Int, _ input: MaintenanceEntryInput) async throws -> MaintenanceEntry {
        try await client.post("vehicles/\(vehicleID)/maintenance-entries", body: input)
    }

    func due() async throws -> DueResponse {
        try await client.get("due")
    }
}

#if DEBUG
/// In-memory activity data for previews and tests.
@MainActor
final class InMemoryActivityRepository: ActivityRepository {
    private(set) var fuel: [Int: [FuelEntry]]
    private(set) var maintenance: [Int: [MaintenanceEntry]]
    private var nextID = 1000
    var failure: Error?

    init(
        fuel: [Int: [FuelEntry]] = [1: InMemoryActivityRepository.sampleFuel],
        maintenance: [Int: [MaintenanceEntry]] = [1: InMemoryActivityRepository.sampleMaintenance]
    ) {
        self.fuel = fuel
        self.maintenance = maintenance
    }

    func fuelEntries(vehicleID: Int) async throws -> [FuelEntry] {
        if let failure { throw failure }
        return (fuel[vehicleID] ?? []).sorted { $0.date > $1.date }
    }

    func createFuelEntry(vehicleID: Int, _ input: FuelEntryInput) async throws -> FuelEntry {
        if let failure { throw failure }
        let cost = input.totalCost ?? (input.pricePerGallon ?? 0) * input.gallons
        let entry = FuelEntry(
            id: nextID, vehicleId: vehicleID, date: input.date, odometer: input.odometer,
            gallons: input.gallons, totalCost: cost, isFullTank: input.isFullTank,
            stationName: input.stationName, notes: input.notes,
            costPerGallon: input.gallons > 0 ? cost / input.gallons : 0, mpg: nil
        )
        nextID += 1
        fuel[vehicleID, default: []].append(entry)
        return entry
    }

    func maintenanceEntries(vehicleID: Int) async throws -> [MaintenanceEntry] {
        if let failure { throw failure }
        return (maintenance[vehicleID] ?? []).sorted { $0.date > $1.date }
    }

    func createMaintenanceEntry(vehicleID: Int, _ input: MaintenanceEntryInput) async throws -> MaintenanceEntry {
        if let failure { throw failure }
        let entry = MaintenanceEntry(
            id: nextID, vehicleId: vehicleID, date: input.date, odometer: input.odometer,
            serviceType: input.serviceType, cost: input.cost, partsUsed: input.partsUsed,
            notes: input.notes, nextDueOdometer: input.nextDueOdometer, nextDueDate: input.nextDueDate
        )
        nextID += 1
        maintenance[vehicleID, default: []].append(entry)
        return entry
    }

    func due() async throws -> DueResponse {
        if let failure { throw failure }
        return DueResponse(items: [], generatedAt: "preview", warnings: nil)
    }

    static let sampleFuel: [FuelEntry] = [
        FuelEntry(id: 1, vehicleId: 1, date: CalendarDate(year: 2024, month: 1, day: 3),
                  odometer: 61_000, gallons: 11.2, totalCost: 41.10, isFullTank: true,
                  stationName: "Costco", notes: nil, costPerGallon: 3.67, mpg: nil),
        FuelEntry(id: 2, vehicleId: 1, date: CalendarDate(year: 2024, month: 1, day: 17),
                  odometer: 61_360, gallons: 10.9, totalCost: 39.90, isFullTank: true,
                  stationName: "Shell", notes: nil, costPerGallon: 3.66, mpg: 33.0),
        FuelEntry(id: 3, vehicleId: 1, date: CalendarDate(year: 2024, month: 1, day: 28),
                  odometer: 61_540, gallons: 5.0, totalCost: 18.50, isFullTank: false,
                  stationName: nil, notes: "splash and dash", costPerGallon: 3.70, mpg: nil),
    ]

    static let sampleMaintenance: [MaintenanceEntry] = [
        MaintenanceEntry(id: 1, vehicleId: 1, date: CalendarDate(year: 2023, month: 11, day: 4),
                         odometer: 58_000, serviceType: "Oil change", cost: 62,
                         partsUsed: [Part(name: "Filter", cost: 11), Part(name: "5qt 0W-20", cost: 34)],
                         notes: nil, nextDueOdometer: 63_000,
                         nextDueDate: CalendarDate(year: 2024, month: 5, day: 4)),
    ]
}
#endif

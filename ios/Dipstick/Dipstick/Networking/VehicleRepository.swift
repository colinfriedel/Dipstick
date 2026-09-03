import Foundation

/// What the vehicle screens need from the backend. Defining it as a protocol lets
/// view models be tested and previewed against an in-memory fake instead of a
/// live server — the "depend on an abstraction" half of dependency injection.
protocol VehicleRepository {
    func list() async throws -> [Vehicle]
    func get(id: Int) async throws -> Vehicle
    func create(_ input: VehicleInput) async throws -> Vehicle
    func update(id: Int, with input: VehicleInput) async throws -> Vehicle
    func delete(id: Int) async throws
}

/// The real implementation: maps each method to a vehicle-service HTTP call.
struct APIVehicleRepository: VehicleRepository {
    let client: APIClient

    func list() async throws -> [Vehicle] {
        try await client.get("vehicles")
    }

    func get(id: Int) async throws -> Vehicle {
        try await client.get("vehicles/\(id)")
    }

    func create(_ input: VehicleInput) async throws -> Vehicle {
        try await client.post("vehicles", body: input)
    }

    func update(id: Int, with input: VehicleInput) async throws -> Vehicle {
        try await client.put("vehicles/\(id)", body: input)
    }

    func delete(id: Int) async throws {
        try await client.delete("vehicles/\(id)")
    }
}

#if DEBUG
/// An in-memory stand-in used by Xcode Previews and unit tests. Behaves like a
/// tiny server: assigns ids, keeps a list, can be told to fail.
@MainActor
final class InMemoryVehicleRepository: VehicleRepository {
    private(set) var vehicles: [Vehicle]
    private var nextID: Int

    /// When set, `list()` throws this instead of returning.
    var listError: Error?

    init(vehicles: [Vehicle] = InMemoryVehicleRepository.sample) {
        self.vehicles = vehicles
        self.nextID = (vehicles.map(\.id).max() ?? 0) + 1
    }

    func list() async throws -> [Vehicle] {
        if let listError { throw listError }
        return vehicles
    }

    func get(id: Int) async throws -> Vehicle {
        guard let match = vehicles.first(where: { $0.id == id }) else {
            throw APIError.http(status: 404, message: "vehicle not found")
        }
        return match
    }

    func create(_ input: VehicleInput) async throws -> Vehicle {
        let vehicle = Vehicle(
            id: nextID, name: input.name, year: input.year, make: input.make,
            model: input.model, vin: input.vin, currentOdometer: input.currentOdometer
        )
        nextID += 1
        vehicles.append(vehicle)
        return vehicle
    }

    func update(id: Int, with input: VehicleInput) async throws -> Vehicle {
        guard let index = vehicles.firstIndex(where: { $0.id == id }) else {
            throw APIError.http(status: 404, message: "vehicle not found")
        }
        vehicles[index] = Vehicle(
            id: id, name: input.name, year: input.year, make: input.make,
            model: input.model, vin: input.vin, currentOdometer: input.currentOdometer
        )
        return vehicles[index]
    }

    func delete(id: Int) async throws {
        vehicles.removeAll { $0.id == id }
    }

    static let sample: [Vehicle] = [
        Vehicle(id: 1, name: "Daily Driver", year: 2018, make: "Honda",
                model: "Civic", vin: nil, currentOdometer: 62_540),
        Vehicle(id: 2, name: "Project Car", year: 1994, make: "Mazda",
                model: "MX-5 Miata", vin: "JM1NA3510R0300000", currentOdometer: 148_902),
    ]
}
#endif

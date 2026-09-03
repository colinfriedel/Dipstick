import Testing
@testable import Dipstick

@MainActor
struct VehicleListViewModelTests {

    @Test func loadSortsVehiclesByNameCaseInsensitively() async {
        let repo = InMemoryVehicleRepository(vehicles: [
            Vehicle(id: 1, name: "zephyr", year: nil, make: nil, model: nil, vin: nil, currentOdometer: 0),
            Vehicle(id: 2, name: "Apex", year: nil, make: nil, model: nil, vin: nil, currentOdometer: 0),
        ])
        let viewModel = VehicleListViewModel(repository: repo)

        await viewModel.load()

        #expect(viewModel.vehicles.map(\.name) == ["Apex", "zephyr"])
        #expect(viewModel.loadFailure == nil)
        #expect(viewModel.isLoading == false)
    }

    @Test func loadSurfacesFailureMessage() async {
        let repo = InMemoryVehicleRepository(vehicles: [])
        repo.listError = APIError.http(status: 500, message: "boom")
        let viewModel = VehicleListViewModel(repository: repo)

        await viewModel.load()

        #expect(viewModel.vehicles.isEmpty)
        #expect(viewModel.loadFailure == "boom")
    }

    @Test func deleteRemovesFromListAndFromServer() async {
        let repo = InMemoryVehicleRepository()
        let viewModel = VehicleListViewModel(repository: repo)
        await viewModel.load()
        let target = viewModel.vehicles[0]

        await viewModel.delete(target)

        #expect(!viewModel.vehicles.contains { $0.id == target.id })
        let serverSide = try? await repo.list()
        #expect(serverSide?.contains { $0.id == target.id } == false)
        #expect(viewModel.actionError == nil)
    }

    @Test func failedDeleteRestoresListAndReportsError() async {
        let repo = FailingDeleteRepository()
        let viewModel = VehicleListViewModel(repository: repo)
        await viewModel.load()
        let countBefore = viewModel.vehicles.count

        await viewModel.delete(viewModel.vehicles[0])

        #expect(viewModel.vehicles.count == countBefore)
        #expect(viewModel.actionError != nil)
    }
}

/// A repository whose `delete` always fails, for the rollback test.
@MainActor
private final class FailingDeleteRepository: VehicleRepository {
    private let backing = InMemoryVehicleRepository()

    func list() async throws -> [Vehicle] { try await backing.list() }
    func get(id: Int) async throws -> Vehicle { try await backing.get(id: id) }
    func create(_ input: VehicleInput) async throws -> Vehicle { try await backing.create(input) }
    func update(id: Int, with input: VehicleInput) async throws -> Vehicle { try await backing.update(id: id, with: input) }
    func delete(id: Int) async throws { throw APIError.http(status: 503, message: "unavailable") }
}

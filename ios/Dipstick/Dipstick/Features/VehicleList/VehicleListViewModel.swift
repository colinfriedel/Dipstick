import Foundation

/// State and actions for the vehicle list screen. The view binds to this and
/// stays free of networking and error-handling logic.
@Observable
@MainActor
final class VehicleListViewModel {
    private(set) var vehicles: [Vehicle] = []
    private(set) var isLoading = false
    /// Non-nil when the initial load failed and we have nothing to show.
    private(set) var loadFailure: String?
    /// Non-nil when a one-off action (like a delete) failed; shown as an alert.
    var actionError: String?

    private let repository: any VehicleRepository

    init(repository: any VehicleRepository = AppEnvironment.vehicleRepository) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        loadFailure = nil
        defer { isLoading = false }

        do {
            let fetched = try await repository.list()
            vehicles = fetched.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            loadFailure = error.localizedDescription
        }
    }

    /// Removes the vehicle from the list immediately (optimistic), then tells the
    /// server. If the server call fails, we re-sync and surface the error.
    func delete(_ vehicle: Vehicle) async {
        let previous = vehicles
        vehicles.removeAll { $0.id == vehicle.id }

        do {
            try await repository.delete(id: vehicle.id)
        } catch {
            vehicles = previous
            actionError = "Couldn't delete \(vehicle.name): \(error.localizedDescription)"
        }
    }
}

import Foundation

/// Loads and holds one vehicle's fuel entries (newest first — the backend
/// already sorts them that way).
@Observable
@MainActor
final class FuelLogViewModel {
    private(set) var entries: [FuelEntry] = []
    private(set) var isLoading = false
    private(set) var loadFailure: String?

    let vehicleID: Int
    private let repository: any ActivityRepository

    init(vehicleID: Int, repository: (any ActivityRepository)? = nil) {
        self.vehicleID = vehicleID
        self.repository = repository ?? AppEnvironment.activityRepository
    }

    func load() async {
        isLoading = true
        loadFailure = nil
        defer { isLoading = false }
        do {
            entries = try await repository.fuelEntries(vehicleID: vehicleID)
        } catch {
            loadFailure = error.localizedDescription
        }
    }
}

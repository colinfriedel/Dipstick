import Foundation

/// Loads and holds one vehicle's maintenance entries (newest first).
@Observable
@MainActor
final class MaintenanceLogViewModel {
    private(set) var entries: [MaintenanceEntry] = []
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
            entries = try await repository.maintenanceEntries(vehicleID: vehicleID)
        } catch {
            loadFailure = error.localizedDescription
        }
    }
}

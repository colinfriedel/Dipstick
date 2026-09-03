import Foundation

/// App-wide configuration and shared dependencies. One place to change the
/// backend URL, and the seam where the real repositories are constructed.
@MainActor
enum AppEnvironment {
    /// vehicle-service's base URL. Defaults to the local Docker stack; override
    /// with a `DIPSTICK_VEHICLE_URL` environment variable in the run scheme to
    /// point at a deployed backend.
    static let vehicleServiceURL: URL = {
        if let raw = ProcessInfo.processInfo.environment["DIPSTICK_VEHICLE_URL"],
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "http://localhost:8081")!
    }()

    /// The shared vehicle repository the views use by default.
    static let vehicleRepository: any VehicleRepository =
        APIVehicleRepository(client: APIClient(baseURL: vehicleServiceURL))
}

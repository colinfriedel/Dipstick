import Foundation

/// App-wide configuration and shared dependencies.
///
/// The backend URL is resolved fresh on every access, in this order:
///   1. the in-app override the user typed in Settings (persisted in UserDefaults)
///   2. the `DIPSTICK_VEHICLE_URL` environment variable (set in the Xcode scheme)
///   3. the built-in default
///
/// The built-in default is the deployed backend, so the app works with no setup
/// when it's just installed and run. For local development against the Docker
/// stack, set the override to your Mac (e.g. `http://Colins-MacBook-Air.local:8081`).
@MainActor
enum AppEnvironment {

    /// UserDefaults key for the in-app backend override.
    static let backendOverrideKey = "backendBaseURLOverride"

    /// Where the app points when nothing overrides it.
    ///
    /// TODO(milestone 8): replace with the real deployed HTTPS URL. Until the
    /// backend is deployed this is the local Docker stack, which only works when
    /// the phone is on the same network as the Mac.
    static let defaultBackendURLString = "http://localhost:8081"

    /// The effective backend base URL right now.
    static var vehicleServiceURL: URL {
        if let override = normalizedURL(UserDefaults.standard.string(forKey: backendOverrideKey)) {
            return override
        }
        if let fromEnvironment = normalizedURL(ProcessInfo.processInfo.environment["DIPSTICK_VEHICLE_URL"]) {
            return fromEnvironment
        }
        return URL(string: defaultBackendURLString)!
    }

    /// A repository wired to the current backend URL. Computed (not stored) so a
    /// changed URL takes effect — the app root also rebuilds on change, so live
    /// screens pick up the new value.
    static var vehicleRepository: any VehicleRepository {
        APIVehicleRepository(client: APIClient(baseURL: vehicleServiceURL))
    }

    /// Turns loose user input into a URL: trims it, and adds `http://` if no
    /// scheme was given. Returns nil for empty/garbage input.
    static func normalizedURL(_ raw: String?) -> URL? {
        guard var string = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else {
            return nil
        }
        if !string.contains("://") {
            string = "http://" + string
        }
        guard let url = URL(string: string), url.host != nil else { return nil }
        return url
    }
}

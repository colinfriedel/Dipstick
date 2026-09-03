import Foundation

/// App-wide configuration and shared dependencies.
///
/// Each backend service's URL is resolved fresh on every access, in this order:
///   1. the in-app override the user typed in Settings (persisted in UserDefaults)
///   2. a `DIPSTICK_*_URL` environment variable (set in the Xcode scheme)
///   3. the built-in default (the local Docker stack)
///
/// For local development against `docker compose`, set both overrides to your Mac
/// (e.g. `http://Colins-MacBook-Air.local:8081` and `…:8082`).
@MainActor
enum AppEnvironment {

    // MARK: URL resolution

    /// UserDefaults keys for the in-app overrides.
    static let vehicleOverrideKey = "backendBaseURLOverride"       // kept from M5
    static let activityOverrideKey = "activityBaseURLOverride"

    static let defaultVehicleURLString = "http://localhost:8081"
    static let defaultActivityURLString = "http://localhost:8082"

    static var vehicleServiceURL: URL {
        resolve(overrideKey: vehicleOverrideKey,
                envKey: "DIPSTICK_VEHICLE_URL",
                default: defaultVehicleURLString)
    }

    static var activityServiceURL: URL {
        resolve(overrideKey: activityOverrideKey,
                envKey: "DIPSTICK_ACTIVITY_URL",
                default: defaultActivityURLString)
    }

    private static func resolve(overrideKey: String, envKey: String, default fallback: String) -> URL {
        if let override = normalizedURL(UserDefaults.standard.string(forKey: overrideKey)) {
            return override
        }
        if let fromEnvironment = normalizedURL(ProcessInfo.processInfo.environment[envKey]) {
            return fromEnvironment
        }
        return URL(string: fallback)!
    }

    /// The value the app root keys its `.id` off, so any URL change reloads every screen.
    static var configurationFingerprint: String {
        vehicleServiceURL.absoluteString + "|" + activityServiceURL.absoluteString
    }

    // MARK: Repositories

    static var vehicleRepository: any VehicleRepository {
        APIVehicleRepository(client: APIClient(baseURL: vehicleServiceURL))
    }

    static var activityRepository: any ActivityRepository {
        APIActivityRepository(client: APIClient(baseURL: activityServiceURL))
    }

    // MARK: Helpers

    /// Turns loose user input into a URL: trims it, adds `http://` if no scheme
    /// was given. Returns nil for empty/garbage input.
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

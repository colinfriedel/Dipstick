import Foundation

/// Every failure path the networking layer can produce, as one type the UI can
/// switch on or just show `.localizedDescription` for.
enum APIError: LocalizedError {
    /// The server couldn't be reached at all (offline, backend not running, DNS).
    case transportFailed(underlying: Error)
    /// We got a response but it wasn't HTTP.
    case notHTTP
    /// A non-2xx status. `message` is the backend's `{"error": "..."}` text when present.
    case http(status: Int, message: String?)
    /// A 2xx response whose body didn't match the expected shape.
    case decodingFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .transportFailed:
            return "Couldn't reach the server. Check that the backend is running and reachable."
        case .notHTTP:
            return "The server sent a response the app didn't understand."
        case .http(let status, let message):
            if let message, !message.isEmpty { return message }
            return "The server returned an error (HTTP \(status))."
        case .decodingFailed:
            return "The server's response didn't match what the app expected."
        }
    }
}

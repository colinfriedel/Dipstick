import Foundation

/// A thin async wrapper around `URLSession` for a JSON REST API. It knows nothing
/// about vehicles or fuel — just: build a request to `baseURL + path`, send it,
/// map HTTP errors to `APIError`, and encode/decode JSON bodies.
///
/// Repositories (e.g. `APIVehicleRepository`) sit on top of this and expose
/// domain methods like `list()` / `create(_:)`.
struct APIClient {
    let baseURL: URL
    var session: URLSession = .shared

    // MARK: Verbs

    func get<Response: Decodable>(_ path: String) async throws -> Response {
        try await sendReturningJSON(makeRequest(path, method: "GET"))
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await sendReturningJSON(makeRequest(path, method: "POST", body: body))
    }

    func put<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await sendReturningJSON(makeRequest(path, method: "PUT", body: body))
    }

    func delete(_ path: String) async throws {
        _ = try await performAndValidate(makeRequest(path, method: "DELETE"))
    }

    // MARK: Request building

    private func makeRequest(_ path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func makeRequest<Body: Encodable>(_ path: String, method: String, body: Body) throws -> URLRequest {
        var request = makeRequest(path, method: method)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    // MARK: Sending

    private func sendReturningJSON<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data = try await performAndValidate(request)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.decodingFailed(underlying: error)
        }
    }

    /// Sends the request, throws for any non-2xx status, and returns the raw body.
    private func performAndValidate(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transportFailed(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.notHTTP
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, message: Self.serverErrorMessage(from: data))
        }
        return data
    }

    /// The backend sends `{"error": "..."}` on failures — pull that out for display.
    private static func serverErrorMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable { let error: String }
        return try? JSONDecoder().decode(ErrorBody.self, from: data).error
    }
}

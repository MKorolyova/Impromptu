//
//  APIClient.swift
//  Impromptu-app
//

import Foundation

protocol APIClient {
    func send<Response: Decodable>(_ endpoint: Endpoint) async throws -> Response
    func send(_ endpoint: Endpoint) async throws
}

/// Values from Config/Config.xcconfig (and the gitignored Config/Secrets.xcconfig),
/// passed through Config/App-Info.plist.
enum APIConfig {
    static let baseURL: URL = infoValue("APIBaseURL").flatMap(URL.init(string:))
        ?? URL(string: "http://localhost:3000/api/v1/")!

    /// The server's shared `API_KEY`, if it has one. Nil sends no `Authorization` header.
    static let apiKey: String? = infoValue("APIKey")

    /// Scheme of the server's `APP_REDIRECT_URL`, where Google Calendar sign-in returns to the app.
    static let calendarCallbackScheme: String = infoValue("CalendarCallbackScheme") ?? "impromptu"

    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else { return nil }
        return value
    }
}

final class URLSessionAPIClient: APIClient {
    private let baseURL: URL
    private let apiKey: String?
    private let session: URLSession

    init(baseURL: URL = APIConfig.baseURL, apiKey: String? = APIConfig.apiKey, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    func send<Response: Decodable>(_ endpoint: Endpoint) async throws -> Response {
        let data = try await perform(endpoint)
        do {
            return try JSONDecoder.api.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    func send(_ endpoint: Endpoint) async throws {
        _ = try await perform(endpoint)
    }

    private func perform(_ endpoint: Endpoint) async throws -> Data {
        let request = try makeRequest(for: endpoint)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(statusCode: -1, code: nil, message: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = try? JSONDecoder.api.decode(APIErrorBody.self, from: data)
            throw APIError.http(statusCode: http.statusCode, code: body?.error.code, message: body?.error.message)
        }
        return data
    }

    private func makeRequest(for endpoint: Endpoint) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appending(path: endpoint.path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL(endpoint.path)
        }
        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }
        guard let url = components.url else { throw APIError.invalidURL(endpoint.path) }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}

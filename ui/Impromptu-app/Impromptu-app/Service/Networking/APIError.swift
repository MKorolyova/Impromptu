//
//  APIError.swift
//  Impromptu-app
//

import Foundation

/// `error.code` values from api/src/utils/api-response.ts.
enum APIErrorCode: String, Decodable {
    case unauthorized = "UNAUTHORIZED"
    case forbidden = "FORBIDDEN"
    case notFound = "NOT_FOUND"
    case validationFailed = "VALIDATION_FAILED"
    case conflict = "CONFLICT"
    case rateLimited = "RATE_LIMITED"
    case `internal` = "INTERNAL"
}

enum APIError: LocalizedError {
    case invalidURL(String)
    case transport(Error)
    case http(statusCode: Int, code: APIErrorCode?, message: String?)
    case decoding(Error)

    var code: APIErrorCode? {
        if case .http(_, let code, _) = self { code } else { nil }
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL(let path): "Invalid request URL: \(path)"
        case .transport(let error): error.localizedDescription
        case .http(_, .unauthorized, let message) where message?.contains("API key") ?? true:
            "The server requires an API key. Set API_KEY in Config/Secrets.xcconfig to match the server's."
        case .http(let status, _, let message): message ?? "Request failed (\(status))."
        case .decoding: "Received an unexpected response from the server."
        }
    }
}

/// Error body: `{ "error": { "code": "...", "message": "..." } }`.
struct APIErrorBody: Decodable {
    struct Detail: Decodable {
        var code: APIErrorCode?
        var message: String
    }

    var error: Detail
}

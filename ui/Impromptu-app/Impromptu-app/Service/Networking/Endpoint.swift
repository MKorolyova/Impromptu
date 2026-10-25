//
//  Endpoint.swift
//  Impromptu-app
//

import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// A description of one API request. Services build these; `APIClient` sends them.
struct Endpoint {
    var method: HTTPMethod
    var path: String
    var queryItems: [URLQueryItem] = []
    var body: Data?

    static func get(_ path: String, query: [URLQueryItem] = []) -> Endpoint {
        Endpoint(method: .get, path: path, queryItems: query)
    }

    static func post(_ path: String, body: some Encodable) throws -> Endpoint {
        Endpoint(method: .post, path: path, body: try JSONEncoder.api.encode(body))
    }

    static func put(_ path: String, body: some Encodable) throws -> Endpoint {
        Endpoint(method: .put, path: path, body: try JSONEncoder.api.encode(body))
    }

    static func delete(_ path: String) -> Endpoint {
        Endpoint(method: .delete, path: path)
    }
}

// MARK: - Routes
// Mirrors api/openapi.yaml. Paths are relative to `APIConfig.baseURL` (…/api/v1/).

extension Endpoint {
    static func login(_ request: LoginRequest) throws -> Endpoint {
        try post("auth/login", body: request)
    }

    static func createUser(_ request: CreateUserRequest) throws -> Endpoint {
        try post("users", body: request)
    }

    static let people = get("feed")

    static func updateLocation(_ request: UpdateLocationRequest, for userId: UUID) throws -> Endpoint {
        try put("\(userPath(userId))/location", body: request)
    }

    static func deleteLocation(for userId: UUID) -> Endpoint {
        delete("\(userPath(userId))/location")
    }

    static func noteRequests(for userId: UUID) -> Endpoint {
        get("\(userPath(userId))/note-requests")
    }

    static func createNoteRequests(_ request: CreateNoteRequestsRequest, for userId: UUID) throws -> Endpoint {
        try post("\(userPath(userId))/note-requests", body: request)
    }

    static func replyToNoteRequest(_ requestId: UUID, reply: NoteReplyRequest, for userId: UUID) throws -> Endpoint {
        try post("\(userPath(userId))/note-requests/\(requestId.pathComponent)/reply", body: reply)
    }

    static func declineNoteRequest(_ requestId: UUID, for userId: UUID) -> Endpoint {
        Endpoint(method: .post, path: "\(userPath(userId))/note-requests/\(requestId.pathComponent)/decline")
    }

    static func nearby(for userId: UUID, radiusMeters: Int) -> Endpoint {
        get("\(userPath(userId))/nearby", query: [URLQueryItem(name: "radiusMeters", value: String(radiusMeters))])
    }

    static func user(_ userId: UUID) -> Endpoint {
        get(userPath(userId))
    }

    static func deleteUser(_ userId: UUID) -> Endpoint {
        delete(userPath(userId))
    }

    static func activities(for userId: UUID) -> Endpoint {
        get("\(userPath(userId))/activities")
    }

    static func createActivity(_ request: CreateActivityRequest, for userId: UUID) throws -> Endpoint {
        try post("\(userPath(userId))/activities", body: request)
    }

    static func deleteActivity(_ activityId: UUID, for userId: UUID) -> Endpoint {
        delete("\(userPath(userId))/activities/\(activityId.pathComponent)")
    }

    static func statuses(for userId: UUID, activeOnly: Bool = false) -> Endpoint {
        get("\(userPath(userId))/statuses", query: activeOnly ? [URLQueryItem(name: "active", value: "true")] : [])
    }

    static func createStatus(_ request: CreateStatusRequest, for userId: UUID) throws -> Endpoint {
        try post("\(userPath(userId))/statuses", body: request)
    }

    static func deleteStatus(_ statusId: UUID, for userId: UUID) -> Endpoint {
        delete("\(userPath(userId))/statuses/\(statusId.pathComponent)")
    }

    private static func userPath(_ userId: UUID) -> String {
        "users/\(userId.pathComponent)"
    }
}

private extension UUID {
    var pathComponent: String { uuidString.lowercased() }
}

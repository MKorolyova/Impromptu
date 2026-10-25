//
//  User.swift
//  Impromptu-app
//

import Foundation

/// `User` in api/openapi.yaml.
struct User: Codable, Identifiable, Hashable {
    let id: UUID
    var email: String
    var firstName: String
    var lastName: String
    var nickname: String?
    var timezone: String

    var displayName: String {
        nickname ?? firstName
    }
}

/// Body of `POST /auth/login`.
struct LoginRequest: Encodable {
    var email: String
    var password: String
}

/// Body of `POST /users`.
struct CreateUserRequest: Encodable {
    var email: String
    var password: String
    var firstName: String
    var lastName: String
    var nickname: String?
    var timezone: String = TimeZone.current.identifier
}

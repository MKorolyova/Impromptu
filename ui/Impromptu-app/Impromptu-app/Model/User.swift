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

    /// The nickname if there is one, otherwise the full name.
    var displayName: String {
        nickname ?? fullName
    }

    var fullName: String {
        "\(firstName) \(lastName)"
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

/// Body of `PATCH /users/{userId}`.
struct UpdateUserRequest: Encodable {
    var firstName: String
    var lastName: String
    /// Nil removes the nickname, so it's always sent.
    var nickname: String?

    private enum CodingKeys: String, CodingKey {
        case firstName, lastName, nickname
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(firstName, forKey: .firstName)
        try container.encode(lastName, forKey: .lastName)
        try container.encode(nickname, forKey: .nickname)
    }
}

/// Body of `POST /users/search`.
struct SearchUsersRequest: Encodable {
    var email: String
}

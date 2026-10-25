//
//  Friend.swift
//  Impromptu-app
//

import Foundation

/// `Friend` in api/openapi.yaml: someone you added, and what you let them see.
struct Friend: Codable, Identifiable, Hashable {
    let id: UUID
    var firstName: String
    var lastName: String
    var nickname: String?
    var canSeeLocation: Bool
    var canSeeNotes: Bool

    var displayName: String {
        nickname ?? "\(firstName) \(lastName)"
    }
}

/// Which of your things a friend can see. Nil leaves that one unchanged.
/// Body of `PATCH /users/{userId}/friends/{friendId}`.
struct FriendAccess: Encodable, Equatable {
    var canSeeLocation: Bool?
    var canSeeNotes: Bool?
}

/// Body of `POST /users/{userId}/friends`: who to add, by email or by user ID (exactly one).
struct AddFriendRequest: Encodable {
    var email: String?
    var friendId: UUID?
    var canSeeLocation: Bool?
    var canSeeNotes: Bool?
}

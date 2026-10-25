//
//  FriendService.swift
//  Impromptu-app
//

import Foundation

protocol FriendServicing {
    func fetchFriends(for userId: UUID) async throws -> [Friend]
    /// Adds someone by email, or changes what they can see if they're already a friend.
    /// Fails with `.notFound` when no one uses that email.
    func addFriend(email: String, access: FriendAccess, for userId: UUID) async throws -> Friend
    func updateFriend(_ friendId: UUID, access: FriendAccess, for userId: UUID) async throws -> Friend
    func removeFriend(_ friendId: UUID, for userId: UUID) async throws
}

private struct FriendsEnvelope: Decodable {
    var friends: [Friend]
}

private struct FriendEnvelope: Decodable {
    var friend: Friend
}

final class FriendService: FriendServicing {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchFriends(for userId: UUID) async throws -> [Friend] {
        let envelope: FriendsEnvelope = try await client.send(.friends(for: userId))
        return envelope.friends
    }

    func addFriend(email: String, access: FriendAccess, for userId: UUID) async throws -> Friend {
        let request = AddFriendRequest(email: email, canSeeLocation: access.canSeeLocation, canSeeNotes: access.canSeeNotes)
        let envelope: FriendEnvelope = try await client.send(.addFriend(request, for: userId))
        return envelope.friend
    }

    func updateFriend(_ friendId: UUID, access: FriendAccess, for userId: UUID) async throws -> Friend {
        let envelope: FriendEnvelope = try await client.send(.updateFriend(friendId, access: access, for: userId))
        return envelope.friend
    }

    func removeFriend(_ friendId: UUID, for userId: UUID) async throws {
        try await client.send(.removeFriend(friendId, for: userId))
    }
}

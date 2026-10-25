//
//  AccountService.swift
//  Impromptu-app
//

import Foundation

/// The API issues no session token yet: after logging in, the app stays signed
/// in by remembering the user's ID.
protocol AccountServicing {
    var storedUserId: UUID? { get }
    func logIn(email: String, password: String) async throws -> User
    func createAccount(_ request: CreateUserRequest) async throws -> User
    /// Lets sign-up catch a taken email before asking for anything else.
    func isEmailRegistered(_ email: String) async throws -> Bool
    func updateProfile(_ request: UpdateUserRequest, for userId: UUID) async throws -> User
    /// Reloads the remembered user on launch.
    func restoreUser(_ userId: UUID) async throws -> User
    func signOut()
    func deleteAccount(_ userId: UUID) async throws
}

private struct UserEnvelope: Decodable {
    var user: User
}

private struct UsersEnvelope: Decodable {
    var users: [User]
}

final class AccountService: AccountServicing {
    private let client: APIClient
    private let defaults: UserDefaults
    private let userIdKey = "currentUserId"

    init(client: APIClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
    }

    private(set) var storedUserId: UUID? {
        get { defaults.string(forKey: userIdKey).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: userIdKey) }
    }

    func logIn(email: String, password: String) async throws -> User {
        let envelope: UserEnvelope = try await client.send(.login(LoginRequest(email: email, password: password)))
        storedUserId = envelope.user.id
        return envelope.user
    }

    func createAccount(_ request: CreateUserRequest) async throws -> User {
        let envelope: UserEnvelope = try await client.send(.createUser(request))
        storedUserId = envelope.user.id
        return envelope.user
    }

    func isEmailRegistered(_ email: String) async throws -> Bool {
        let envelope: UsersEnvelope = try await client.send(.searchUsers(SearchUsersRequest(email: email)))
        return !envelope.users.isEmpty
    }

    func updateProfile(_ request: UpdateUserRequest, for userId: UUID) async throws -> User {
        let envelope: UserEnvelope = try await client.send(.updateUser(request, for: userId))
        return envelope.user
    }

    func restoreUser(_ userId: UUID) async throws -> User {
        let envelope: UserEnvelope = try await client.send(.user(userId))
        return envelope.user
    }

    func signOut() {
        storedUserId = nil
    }

    func deleteAccount(_ userId: UUID) async throws {
        try await client.send(.deleteUser(userId))
        signOut()
    }
}

//
//  SettingsViewModel.swift
//  Impromptu-app
//

import Foundation
import Observation

/// Your name, who can see your location and notes, how your status updates, and your account.
@Observable
final class SettingsViewModel {
    /// One thing you can share with friends; each has its own list.
    enum Audience: String, CaseIterable, Identifiable {
        case location
        case notes

        var id: Self { self }

        func includes(_ friend: Friend) -> Bool {
            switch self {
            case .location: friend.canSeeLocation
            case .notes: friend.canSeeNotes
            }
        }

        func access(_ allowed: Bool) -> FriendAccess {
            switch self {
            case .location: FriendAccess(canSeeLocation: allowed)
            case .notes: FriendAccess(canSeeNotes: allowed)
            }
        }

        var other: Audience {
            self == .location ? .notes : .location
        }
    }

    var firstName: String
    var lastName: String
    var nickname: String
    private(set) var user: User
    private(set) var isSavingProfile = false
    /// Briefly true after the name is saved.
    private(set) var showsProfileSaved = false

    private(set) var friends: [Friend] = []
    private(set) var hasLoadedFriends = false
    private(set) var friendsLoadError: String?
    /// The list the add-friend sheet is open for.
    var addingTo: Audience?
    var friendEmail = ""
    private(set) var isAddingFriend = false
    private(set) var addFriendError: String?

    private(set) var statusSources: Set<StatusSource>
    var errorMessage: String?

    private let services: Services

    init(user: User, services: Services) {
        self.user = user
        self.services = services
        firstName = user.firstName
        lastName = user.lastName
        nickname = user.nickname ?? ""
        statusSources = services.statusPreferences.sources(for: user.id)
    }

    // MARK: Profile

    private var trimmedNickname: String? {
        let nickname = trimmed(nickname)
        return nickname.isEmpty ? nil : nickname
    }

    var hasProfileChanges: Bool {
        trimmed(firstName) != user.firstName || trimmed(lastName) != user.lastName || trimmedNickname != user.nickname
    }

    var canSaveProfile: Bool {
        hasProfileChanges && !isSavingProfile
            && !trimmed(firstName).isEmpty && !trimmed(lastName).isEmpty
            && trimmed(nickname).count <= RegistrationViewModel.maxNicknameLength
    }

    func saveProfile(session: SessionViewModel) async {
        guard canSaveProfile else { return }
        isSavingProfile = true
        defer { isSavingProfile = false }
        do {
            let updated = try await services.account.updateProfile(
                UpdateUserRequest(firstName: trimmed(firstName), lastName: trimmed(lastName), nickname: trimmedNickname),
                for: user.id)
            user = updated
            firstName = updated.firstName
            lastName = updated.lastName
            nickname = updated.nickname ?? ""
            session.updateUser(updated)
            showsProfileSaved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissProfileSaved() {
        showsProfileSaved = false
    }

    // MARK: Friends

    func loadFriends() async {
        friendsLoadError = nil
        do {
            friends = try await services.friends.fetchFriends(for: user.id)
        } catch {
            friendsLoadError = error.localizedDescription
        }
        hasLoadedFriends = true
    }

    func friends(in audience: Audience) -> [Friend] {
        friends.filter(audience.includes)
    }

    /// Friends you could add to this list with one tap.
    func friends(notIn audience: Audience) -> [Friend] {
        friends.filter { !audience.includes($0) }
    }

    func startAdding(to audience: Audience) {
        friendEmail = ""
        addFriendError = nil
        addingTo = audience
    }

    var canAddFriendByEmail: Bool {
        trimmed(friendEmail).contains("@") && !isAddingFriend
    }

    /// Returns whether they were added (the sheet closes on success).
    func addFriendByEmail() async -> Bool {
        guard let audience = addingTo, canAddFriendByEmail else { return false }
        isAddingFriend = true
        addFriendError = nil
        defer { isAddingFriend = false }
        do {
            let friend = try await services.friends.addFriend(email: trimmed(friendEmail), access: audience.access(true), for: user.id)
            upsert(friend)
            addingTo = nil
            return true
        } catch let error as APIError where error.code == .notFound {
            addFriendError = "No one on \(Brand.appName) uses that email. Check it, or ask them to sign up first."
        } catch {
            addFriendError = error.localizedDescription
        }
        return false
    }

    func add(_ friend: Friend, to audience: Audience) async {
        do {
            upsert(try await services.friends.updateFriend(friend.id, access: audience.access(true), for: user.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Takes them off this list. If they're on neither list afterwards, they're removed as a friend.
    func remove(_ friend: Friend, from audience: Audience) async {
        do {
            if audience.other.includes(friend) {
                upsert(try await services.friends.updateFriend(friend.id, access: audience.access(false), for: user.id))
            } else {
                try await services.friends.removeFriend(friend.id, for: user.id)
                friends.removeAll { $0.id == friend.id }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func upsert(_ friend: Friend) {
        if let index = friends.firstIndex(where: { $0.id == friend.id }) {
            friends[index] = friend
        } else {
            friends.append(friend)
            friends.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
    }

    // MARK: Status updates

    func setStatusSource(_ source: StatusSource, isOn: Bool) {
        if isOn {
            statusSources.insert(source)
        } else {
            // Keep at least one way to update.
            guard statusSources.count > 1 else { return }
            statusSources.remove(source)
        }
        services.statusPreferences.save(statusSources, for: user.id)
    }

    // MARK: Account

    func deleteAccount(session: SessionViewModel) async {
        do {
            try await session.deleteAccount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

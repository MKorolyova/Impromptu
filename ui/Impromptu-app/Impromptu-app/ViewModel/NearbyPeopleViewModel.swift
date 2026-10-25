//
//  NearbyPeopleViewModel.swift
//  Impromptu-app
//

import Foundation
import Observation

/// Everyone nearby doing what you're doing, closest first, to pick and ask for a note.
@Observable
final class NearbyPeopleViewModel {
    enum LoadState: Equatable {
        case loading
        /// Nearby alerts are off, so your position isn't being shared.
        case alertsOff
        /// No active status, so there's nothing to match on.
        case noStatus
        case loaded
        case failed(String)
    }

    static let quickPickCount = 3
    /// The server accepts up to 10 recipients per request.
    static let maxSelection = 10

    private(set) var loadState: LoadState = .loading
    private(set) var result: NearbyResult?
    /// People you already have an open request with.
    private(set) var askedIds: Set<UUID> = []
    var selection: Set<UUID> = []
    private(set) var isSending = false
    /// Shown after a request goes out.
    private(set) var confirmation: String?
    var errorMessage: String?

    private let user: User
    private let services: Services

    init(user: User, services: Services) {
        self.user = user
        self.services = services
    }

    /// Closest first, as the server sends them.
    var people: [Person] {
        result?.users ?? []
    }

    var canSend: Bool {
        !selection.isEmpty && !isSending
    }

    func load() async {
        guard services.nearbyAlerts.isEnabled else {
            loadState = .alertsOff
            return
        }
        do {
            let result = try await services.nearbyAlerts.refreshInForeground()
            self.result = result
            loadState = result.activity == nil ? .noStatus : .loaded
            let inbox = try? await services.noteRequests.fetchInbox(for: user.id)
            askedIds = Set((inbox?.outgoing ?? []).filter(\.isOpen).map(\.otherUser.id))
            // Drop anyone who left or was already asked.
            selection = selection.filter { id in people.contains { $0.id == id } && !askedIds.contains(id) }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func isAsked(_ person: Person) -> Bool {
        askedIds.contains(person.id)
    }

    func toggle(_ person: Person) {
        guard !isAsked(person) else { return }
        if selection.contains(person.id) {
            selection.remove(person.id)
        } else if selection.count < Self.maxSelection {
            selection.insert(person.id)
        }
    }

    /// Selects the closest few you haven't asked yet.
    func selectClosest() {
        selection = Set(people.filter { !isAsked($0) }.prefix(Self.quickPickCount).map(\.id))
    }

    func sendRequests() async {
        guard canSend else { return }
        isSending = true
        defer { isSending = false }
        // Keep the screen's order, closest first.
        let recipients = people.filter { selection.contains($0.id) }
        do {
            let response = try await services.noteRequests.requestNotes(from: recipients.map(\.id), for: user.id)
            askedIds.formUnion(recipients.map(\.id))
            selection.removeAll()
            confirmation = Self.confirmation(asked: response.requests.compactMap { request in
                recipients.first { $0.id == request.otherUser.id }?.displayName
            })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func confirmation(asked names: [String]) -> String {
        switch names.count {
        case 0: "They already have a request from you."
        case 1: "Asked \(names[0]). You'll get a notification when they reply."
        case 2: "Asked \(names[0]) and \(names[1]). You'll get a notification when they reply."
        default: "Asked \(names[0]) and \(names.count - 1) others. You'll get a notification when they reply."
        }
    }
}

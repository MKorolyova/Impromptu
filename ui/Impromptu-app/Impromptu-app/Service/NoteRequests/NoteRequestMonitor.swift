//
//  NoteRequestMonitor.swift
//  Impromptu-app
//

import Foundation

/// What's already been announced from the inbox. Persisted between polls.
nonisolated struct NoteActivityState: Codable, Equatable, Sendable {
    var announcedRequestIds: Set<UUID> = []
    /// Your requests whose answer (reply or decline) has been announced.
    var announcedAnswerIds: Set<UUID> = []
    /// False until the first poll, which records what's there without notifying.
    var hasBaseline = false
}

/// Finds what's new in the inbox since the last poll.
enum NoteActivityTracker {
    struct Changes: Equatable {
        /// Open requests sent to you.
        var newRequests: [NoteRequest] = []
        /// Your requests that were answered or declined.
        var newAnswers: [NoteRequest] = []

        var isEmpty: Bool { newRequests.isEmpty && newAnswers.isEmpty }
    }

    static func diff(_ inbox: NoteInbox, since state: NoteActivityState) -> (changes: Changes, state: NoteActivityState) {
        let answered = inbox.outgoing.filter { $0.status != .pending }
        var changes = Changes()
        if state.hasBaseline {
            changes.newRequests = inbox.incoming.filter { $0.isOpen && !state.announcedRequestIds.contains($0.id) }
            changes.newAnswers = answered.filter { !state.announcedAnswerIds.contains($0.id) }
        }
        // Only keep IDs still in the inbox, so the sets don't grow forever.
        let newState = NoteActivityState(
            announcedRequestIds: Set(inbox.incoming.map(\.id)),
            announcedAnswerIds: Set(answered.map(\.id)),
            hasBaseline: true
        )
        return (changes, newState)
    }
}

/// The text of a note-request notification.
struct NoteNotificationMessage: Equatable {
    let title: String
    let body: String

    static func request(_ request: NoteRequest) -> NoteNotificationMessage {
        let name = request.otherUser.displayName
        let doing = request.activity.map { " They're also \(lowercasedFirst($0.name)) nearby." } ?? ""
        return NoteNotificationMessage(title: "\(name) asked for a note", body: "Let them know where you are.\(doing)")
    }

    static func answer(_ request: NoteRequest) -> NoteNotificationMessage {
        let name = request.otherUser.displayName
        guard let reply = request.reply else {
            return NoteNotificationMessage(title: "\(name) can't share right now", body: "They declined your note request.")
        }
        var body = reply.text
        if let place = reply.placeLabel { body += " · \(place)" }
        if reply.location != nil { body += " · 📍 Location shared" }
        return NoteNotificationMessage(title: "\(name) sent you a note", body: body)
    }

    private static func lowercasedFirst(_ text: String) -> String {
        text.prefix(1).lowercased() + text.dropFirst()
    }
}

protocol NoteRequestMonitoring: AnyObject {
    /// Fetches the inbox. With `notify`, posts a notification for each new request or answer;
    /// without it (you're looking at the inbox), just counts them as seen.
    func poll(notify: Bool) async throws -> NoteInbox
    /// Forgets what's been announced, e.g. on sign-out.
    func reset()
}

final class NoteRequestMonitor: NoteRequestMonitoring {
    /// Beyond this many at once, one summary notification instead.
    private static let maxIndividualNotifications = 3

    private let account: AccountServicing
    private let api: NoteRequestServicing
    private let notifications: NotificationPosting
    private let defaults: UserDefaults
    private let stateKey = "noteRequests.state"

    init(account: AccountServicing, api: NoteRequestServicing, notifications: NotificationPosting, defaults: UserDefaults = .standard) {
        self.account = account
        self.api = api
        self.notifications = notifications
        self.defaults = defaults
    }

    private var state: NoteActivityState {
        get { defaults.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(NoteActivityState.self, from: $0) } ?? NoteActivityState() }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: stateKey) }
    }

    func poll(notify: Bool) async throws -> NoteInbox {
        guard let userId = account.storedUserId else { return .empty }
        let inbox = try await api.fetchInbox(for: userId)
        let (changes, newState) = NoteActivityTracker.diff(inbox, since: state)
        state = newState
        if notify, !changes.isEmpty, await notifications.isAuthorized() {
            await announce(changes)
        }
        return inbox
    }

    func reset() {
        defaults.removeObject(forKey: stateKey)
    }

    private func announce(_ changes: NoteActivityTracker.Changes) async {
        let messages = changes.newRequests.map(NoteNotificationMessage.request) + changes.newAnswers.map(NoteNotificationMessage.answer)
        if messages.count > Self.maxIndividualNotifications {
            await notifications.post(id: "notes-\(UUID().uuidString)", title: "\(messages.count) new notes",
                                     body: "People nearby asked for or sent you notes.", route: .notes)
            return
        }
        for message in messages {
            await notifications.post(id: "notes-\(UUID().uuidString)", title: message.title, body: message.body, route: .notes)
        }
    }
}

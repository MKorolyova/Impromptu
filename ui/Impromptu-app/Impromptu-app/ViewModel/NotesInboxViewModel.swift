//
//  NotesInboxViewModel.swift
//  Impromptu-app
//

import Foundation
import Observation

/// What a reply to a note request will say.
struct NoteReplyDraft: Equatable {
    static let maxTextLength = 280
    static let maxPlaceLength = 100

    var text = ""
    var placeLabel = ""
    /// Off by default: sharing your exact position should be a choice.
    var includeLocation = false

    var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedPlace: String? {
        let trimmed = placeLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isValid: Bool {
        !trimmedText.isEmpty && text.count <= Self.maxTextLength && placeLabel.count <= Self.maxPlaceLength
    }
}

/// Requests you've received (to reply to) and sent (to read the replies).
@Observable
final class NotesInboxViewModel {
    enum Tab: String, CaseIterable, Identifiable {
        case received = "Received"
        case sent = "Sent"

        var id: Self { self }
    }

    var tab: Tab
    private(set) var inbox: NoteInbox = .empty
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// The request the reply sheet is open for.
    var replyingTo: NoteRequest?
    var draft = NoteReplyDraft()
    private(set) var isSendingReply = false
    var errorMessage: String?

    private let user: User
    private let services: Services

    init(user: User, services: Services, tab: Tab = .received) {
        self.user = user
        self.services = services
        self.tab = tab
    }

    var requests: [NoteRequest] {
        tab == .received ? inbox.incoming : inbox.outgoing
    }

    func load() async {
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            // You're looking at the inbox, so there's nothing to notify about.
            inbox = try await services.noteMonitor.poll(notify: false)
            // Opened from a notification? Show the side that has something new.
            if !hasLoaded, tab == .received, inbox.openIncomingCount == 0, inbox.outgoing.contains(where: { $0.reply != nil }) {
                tab = .sent
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startReply(to request: NoteRequest) {
        draft = NoteReplyDraft()
        replyingTo = request
    }

    /// Returns whether the reply went out (the sheet closes on success).
    func sendReply() async -> Bool {
        guard let request = replyingTo, draft.isValid else { return false }
        isSendingReply = true
        defer { isSendingReply = false }

        var location: Coordinate?
        if draft.includeLocation {
            location = await services.location.currentLocation()
            guard location != nil else {
                errorMessage = "Couldn't get your location. Turn on Location for Impromptu, or send the note without it."
                return false
            }
        }
        do {
            let answered = try await services.noteRequests.reply(
                to: request, text: draft.trimmedText, placeLabel: draft.trimmedPlace, location: location, for: user.id)
            replace(answered)
            replyingTo = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func decline(_ request: NoteRequest) async {
        do {
            replace(try await services.noteRequests.decline(request, for: user.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func replace(_ request: NoteRequest) {
        if let index = inbox.incoming.firstIndex(where: { $0.id == request.id }) {
            inbox.incoming[index] = request
        } else if let index = inbox.outgoing.firstIndex(where: { $0.id == request.id }) {
            inbox.outgoing[index] = request
        }
    }
}

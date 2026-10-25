//
//  NoteRequest.swift
//  Impromptu-app
//

import Foundation

/// The public slice of a user: what the other side of a note request sees.
struct UserProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var firstName: String
    var lastName: String
    var nickname: String?

    var displayName: String {
        nickname ?? firstName
    }
}

/// `NoteRequest` in api/openapi.yaml: someone nearby asking for a note, and the answer.
struct NoteRequest: Decodable, Identifiable, Hashable {
    enum Direction: String, Decodable {
        /// You were asked.
        case incoming = "INCOMING"
        /// You asked.
        case outgoing = "OUTGOING"
    }

    enum State: String, Decodable {
        case pending = "PENDING"
        case answered = "ANSWERED"
        case declined = "DECLINED"
    }

    struct Reply: Decodable, Hashable {
        var text: String
        var placeLabel: String?
        var location: ReplyLocation?
        var respondedAt: Date
    }

    struct ReplyLocation: Codable, Hashable {
        var latitude: Double
        var longitude: Double
    }

    let id: UUID
    var direction: Direction
    var otherUser: UserProfile
    var activity: ActivitySummary?
    var status: State
    var isExpired: Bool
    var createdAt: Date
    var expiresAt: Date
    var reply: Reply?

    /// Still waiting for the other person, and they can still answer.
    var isOpen: Bool {
        status == .pending && !isExpired && expiresAt > .now
    }
}

/// Response of `GET /users/{userId}/note-requests`.
struct NoteInbox: Decodable, Equatable {
    var incoming: [NoteRequest]
    var outgoing: [NoteRequest]

    static let empty = NoteInbox(incoming: [], outgoing: [])

    /// Requests waiting on you.
    var openIncomingCount: Int {
        incoming.filter(\.isOpen).count
    }
}

/// Body of `POST /users/{userId}/note-requests`.
struct CreateNoteRequestsRequest: Encodable {
    var recipientIds: [UUID]
}

/// Response of `POST /users/{userId}/note-requests`.
struct CreateNoteRequestsResponse: Decodable {
    var requests: [NoteRequest]
    /// Already had an open request from you.
    var skippedRecipientIds: [UUID]
}

/// Body of `POST /users/{userId}/note-requests/{requestId}/reply`.
struct NoteReplyRequest: Encodable {
    var text: String
    var placeLabel: String?
    var latitude: Double?
    var longitude: Double?
}

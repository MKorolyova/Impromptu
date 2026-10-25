//
//  NoteRequestService.swift
//  Impromptu-app
//

import Foundation

protocol NoteRequestServicing {
    func fetchInbox(for userId: UUID) async throws -> NoteInbox
    /// Recipients must be nearby and doing the same activity; the server refuses anyone else.
    func requestNotes(from recipientIds: [UUID], for userId: UUID) async throws -> CreateNoteRequestsResponse
    func reply(to request: NoteRequest, text: String, placeLabel: String?, location: Coordinate?, for userId: UUID) async throws -> NoteRequest
    func decline(_ request: NoteRequest, for userId: UUID) async throws -> NoteRequest
}

private struct NoteRequestEnvelope: Decodable {
    var request: NoteRequest
}

final class NoteRequestService: NoteRequestServicing {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchInbox(for userId: UUID) async throws -> NoteInbox {
        try await client.send(.noteRequests(for: userId))
    }

    func requestNotes(from recipientIds: [UUID], for userId: UUID) async throws -> CreateNoteRequestsResponse {
        try await client.send(.createNoteRequests(CreateNoteRequestsRequest(recipientIds: recipientIds), for: userId))
    }

    func reply(to request: NoteRequest, text: String, placeLabel: String?, location: Coordinate?, for userId: UUID) async throws -> NoteRequest {
        let body = NoteReplyRequest(text: text, placeLabel: placeLabel, latitude: location?.latitude, longitude: location?.longitude)
        let envelope: NoteRequestEnvelope = try await client.send(.replyToNoteRequest(request.id, reply: body, for: userId))
        return envelope.request
    }

    func decline(_ request: NoteRequest, for userId: UUID) async throws -> NoteRequest {
        let envelope: NoteRequestEnvelope = try await client.send(.declineNoteRequest(request.id, for: userId))
        return envelope.request
    }
}

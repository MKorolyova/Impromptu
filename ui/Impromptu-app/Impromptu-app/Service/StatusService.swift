//
//  StatusService.swift
//  Impromptu-app
//

import Foundation

protocol StatusServicing {
    func currentStatus(for userId: UUID) async throws -> Status?
    /// `duration` nil uses the activity's default, applied by the server.
    func setStatus(activity: Activity, note: String?, duration: TimeInterval?, for userId: UUID) async throws -> Status
    func clearStatus(_ status: Status) async throws
}

private struct StatusesEnvelope: Decodable {
    var statuses: [Status]
}

private struct StatusEnvelope: Decodable {
    var status: Status
}

final class StatusService: StatusServicing {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func currentStatus(for userId: UUID) async throws -> Status? {
        // Newest first, so the first active one is current.
        let envelope: StatusesEnvelope = try await client.send(.statuses(for: userId, activeOnly: true))
        return envelope.statuses.first
    }

    func setStatus(activity: Activity, note: String?, duration: TimeInterval?, for userId: UUID) async throws -> Status {
        let request = CreateStatusRequest(
            activityId: activity.id,
            note: note,
            expiresAt: duration.map { Date.now.addingTimeInterval($0) }
        )
        let envelope: StatusEnvelope = try await client.send(.createStatus(request, for: userId))
        return envelope.status
    }

    func clearStatus(_ status: Status) async throws {
        try await client.send(.deleteStatus(status.id, for: status.userId))
    }
}

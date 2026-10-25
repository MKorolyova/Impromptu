//
//  ActivityService.swift
//  Impromptu-app
//

import Foundation

protocol ActivityServicing {
    /// The user's custom activities first, then the standard ones.
    func fetchActivities(for userId: UUID) async throws -> [Activity]
    func createActivity(name: String, durationMinutes: Int, for userId: UUID) async throws -> Activity
    /// Only custom activities can be deleted; the server returns 403 otherwise.
    func deleteActivity(_ activity: Activity, for userId: UUID) async throws
}

private struct ActivitiesEnvelope: Decodable {
    var activities: [Activity]
}

private struct ActivityEnvelope: Decodable {
    var activity: Activity
}

final class ActivityService: ActivityServicing {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func fetchActivities(for userId: UUID) async throws -> [Activity] {
        let envelope: ActivitiesEnvelope = try await client.send(.activities(for: userId))
        return envelope.activities
    }

    func createActivity(name: String, durationMinutes: Int, for userId: UUID) async throws -> Activity {
        let request = CreateActivityRequest(name: name, defaultDurationMinutes: durationMinutes)
        let envelope: ActivityEnvelope = try await client.send(.createActivity(request, for: userId))
        return envelope.activity
    }

    func deleteActivity(_ activity: Activity, for userId: UUID) async throws {
        try await client.send(.deleteActivity(activity.id, for: userId))
    }
}

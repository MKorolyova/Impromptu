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
    /// The ones the user picked as their own at sign-up; empty if they never did.
    func fetchSavedActivities(for userId: UUID) async throws -> [Activity]
    /// Replaces the picked activities and returns them.
    func saveActivities(_ activityIds: [UUID], for userId: UUID) async throws -> [Activity]
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

    func fetchSavedActivities(for userId: UUID) async throws -> [Activity] {
        let envelope: ActivitiesEnvelope = try await client.send(.savedActivities(for: userId))
        return envelope.activities
    }

    func saveActivities(_ activityIds: [UUID], for userId: UUID) async throws -> [Activity] {
        let request = ReplaceSavedActivitiesRequest(activityIds: activityIds)
        let envelope: ActivitiesEnvelope = try await client.send(.replaceSavedActivities(request, for: userId))
        return envelope.activities
    }
}

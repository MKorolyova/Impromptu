//
//  Activity.swift
//  Impromptu-app
//

import Foundation

/// `Activity` in api/openapi.yaml.
struct Activity: Codable, Identifiable, Hashable {
    let id: UUID
    /// Nil for standard activities.
    var ownerId: UUID?
    var name: String
    var iconId: UUID?
    var defaultDurationMinutes: Int
    var isCustom: Bool

    var defaultDuration: TimeInterval {
        TimeInterval(defaultDurationMinutes * 60)
    }

    var summary: ActivitySummary {
        ActivitySummary(id: id, name: name, iconId: iconId, isCustom: isCustom)
    }
}

/// The slice of an activity embedded in a `Status`.
struct ActivitySummary: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var iconId: UUID?
    var isCustom: Bool
}

/// Body of `POST /users/{userId}/activities`.
struct CreateActivityRequest: Encodable {
    var name: String
    var defaultDurationMinutes: Int
}

/// Body of `PUT /users/{userId}/saved-activities`.
struct ReplaceSavedActivitiesRequest: Encodable {
    var activityIds: [UUID]
}

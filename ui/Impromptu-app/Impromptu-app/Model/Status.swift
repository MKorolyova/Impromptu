//
//  Status.swift
//  Impromptu-app
//

import Foundation

/// `status_source` in api/src/db/schema.ts.
enum StatusSource: String, Codable, CaseIterable, Identifiable {
    case manual = "MANUAL"
    case calendar = "CALENDAR"
    case location = "LOCATION"
    case automated = "AUTOMATED"

    var id: Self { self }
}

/// `Status` in api/openapi.yaml.
struct Status: Codable, Identifiable, Hashable {
    let id: UUID
    var userId: UUID
    var activity: ActivitySummary
    var note: String?
    var source: StatusSource
    var startedAt: Date
    var expiresAt: Date

    func isActive(at date: Date = .now) -> Bool {
        startedAt <= date && date < expiresAt
    }
}

/// Body of `POST /users/{userId}/statuses`.
struct CreateStatusRequest: Encodable {
    var activityId: UUID
    var note: String?
    /// Server defaults to now + the activity's `defaultDurationMinutes`.
    var expiresAt: Date?
}

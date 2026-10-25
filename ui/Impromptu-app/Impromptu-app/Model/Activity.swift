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
    /// The user's own activities (database rows).
    var activityIds: [UUID]
    /// Standard activities by name, as `GET /activities` lists them; the server finds or creates their rows.
    var standardActivityNames: [String] = []
}

/// An entry of `GET /activities`: the built-in list of standard activities. No id until someone uses it.
struct StandardActivity: Decodable, Hashable {
    var name: String
    var defaultDurationMinutes: Int
}

/// Something to pick at sign-up: a standard activity from the built-in list, or one of the user's own.
struct ActivityChoice: Identifiable, Hashable {
    enum Source: Hashable {
        case standard
        /// A database row the user created.
        case custom(UUID)
        /// Typed in during sign-up; it becomes a custom row once the account exists.
        case new
    }

    let name: String
    let defaultDurationMinutes: Int
    let source: Source

    var id: String {
        switch source {
        case .standard: "standard:\(name)"
        case .custom(let id): "custom:\(id.uuidString)"
        case .new: "new:\(name.lowercased())"
        }
    }

    /// The user's own, saved or not yet.
    var isCustom: Bool {
        source != .standard
    }

    var isNew: Bool {
        source == .new
    }

    var customId: UUID? {
        if case .custom(let id) = source { id } else { nil }
    }

    init(standard: StandardActivity) {
        name = standard.name
        defaultDurationMinutes = standard.defaultDurationMinutes
        source = .standard
    }

    init(newNamed name: String, defaultDurationMinutes: Int) {
        self.name = name
        self.defaultDurationMinutes = defaultDurationMinutes
        source = .new
    }

    init(custom activity: Activity) {
        name = activity.name
        defaultDurationMinutes = activity.defaultDurationMinutes
        source = .custom(activity.id)
    }
}

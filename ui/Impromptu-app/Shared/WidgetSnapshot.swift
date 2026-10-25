//
//  WidgetSnapshot.swift
//  Impromptu-app
//
//  Compiled into both the app and the widget extension.
//  Deliberately flat and independent of the app's API models so the widget
//  never needs the networking layer.
//

import Foundation

nonisolated struct WidgetSnapshot: Codable, Sendable, Equatable {
    var userName: String?
    /// The user's IANA time zone, shown as "GMT-5" next to their activity.
    var timezone: String?
    var myStatus: StatusSnapshot?
    var friends: [FriendStatusSnapshot]
    var updatedAt: Date

    static let empty = WidgetSnapshot(userName: nil, timezone: nil, myStatus: nil, friends: [], updatedAt: .distantPast)

    /// The friends whose status hasn't expired yet, soonest-expiring last.
    func activeFriends(at date: Date) -> [FriendStatusSnapshot] {
        friends
            .filter { $0.status?.isActive(at: date) == true }
            .sorted { ($0.status?.expiresAt ?? .distantPast) > ($1.status?.expiresAt ?? .distantPast) }
    }

    /// Next moment the widget's content changes on its own.
    func nextExpiry(after date: Date) -> Date? {
        ([myStatus] + friends.map(\.status))
            .compactMap { $0?.expiresAt }
            .filter { $0 > date }
            .min()
    }
}

nonisolated struct StatusSnapshot: Codable, Sendable, Equatable {
    var activityName: String
    var note: String?
    var startedAt: Date
    var expiresAt: Date

    func isActive(at date: Date) -> Bool {
        startedAt <= date && date < expiresAt
    }
}

nonisolated struct FriendStatusSnapshot: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var displayName: String
    var status: StatusSnapshot?
}

nonisolated extension SharedKey where Value == WidgetSnapshot {
    static let widgetSnapshot = SharedKey(fileName: "widget-snapshot.json")
}

nonisolated extension WidgetSnapshot {
    /// Used by the widget gallery and previews.
    static let placeholder: WidgetSnapshot = {
        let now = Date()
        return WidgetSnapshot(
            userName: "Alex",
            timezone: "America/Chicago",
            myStatus: StatusSnapshot(activityName: "Running", note: "Lakeshore loop, back by 7. Come join!", startedAt: now, expiresAt: now.addingTimeInterval(2700)),
            friends: [
                FriendStatusSnapshot(id: UUID(), displayName: "Sam", status: StatusSnapshot(activityName: "Grabbing coffee", note: nil, startedAt: now, expiresAt: now.addingTimeInterval(1800))),
                FriendStatusSnapshot(id: UUID(), displayName: "Jordan", status: StatusSnapshot(activityName: "Studying", note: "Library 3F", startedAt: now, expiresAt: now.addingTimeInterval(5400))),
            ],
            updatedAt: now
        )
    }()
}

//
//  WidgetSyncService.swift
//  Impromptu-app
//

import Foundation
import WidgetKit

protocol WidgetSyncing {
    func sync(user: User?, myStatus: Status?, people: [Person])
    func clear()
    /// Redraws the widget after the app's light/dark choice changes.
    func reloadAppearance()
}

/// Maps app models into the widget's `WidgetSnapshot`, writes it to the
/// App Group container and asks WidgetKit to refresh.
final class WidgetSyncService: WidgetSyncing {
    private let store: SharedStore
    private var lastSnapshot: WidgetSnapshot?

    init(store: SharedStore = .standard) {
        self.store = store
    }

    func sync(user: User?, myStatus: Status?, people: [Person]) {
        var snapshot = WidgetSnapshot(
            userName: user?.displayName,
            timezone: user?.timezone,
            myStatus: myStatus.map { StatusSnapshot($0) },
            friends: people.map { person in
                FriendStatusSnapshot(id: person.id, displayName: person.displayName, status: person.status.map { StatusSnapshot($0) })
            },
            updatedAt: lastSnapshot?.updatedAt ?? .now
        )
        // Skip the disk write and timeline reload when nothing visible changed.
        guard snapshot != lastSnapshot else { return }
        snapshot.updatedAt = .now
        publish(snapshot)
    }

    func clear() {
        store.remove(.widgetSnapshot)
        lastSnapshot = nil
        WidgetCenter.shared.reloadAllTimelines()
    }

    func reloadAppearance() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func publish(_ snapshot: WidgetSnapshot) {
        do {
            try store.save(snapshot, for: .widgetSnapshot)
            lastSnapshot = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            print("WidgetSyncService: failed to save snapshot: \(error)")
        }
    }
}

extension StatusSnapshot {
    /// Also used by the home screen, so it draws your status exactly like the widget.
    init(_ status: Status) {
        self.init(activityName: status.activity.name, note: status.note, startedAt: status.startedAt, expiresAt: status.expiresAt)
    }
}

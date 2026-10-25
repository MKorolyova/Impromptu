//
//  NearbyAlertPolicy.swift
//  Impromptu-app
//

import Foundation

/// What's been announced so far for the current activity. Persisted between checks.
nonisolated struct NearbyAlertState: Codable, Equatable, Sendable {
    /// The activity the people below were matched on. A different activity starts over.
    var activityId: UUID?
    /// Everyone you've already been told about (by notification or by seeing them in the app).
    var announcedUserIds: Set<UUID> = []
    var lastNotifiedAt: Date?
}

nonisolated enum NearbyAlertDecision: Equatable, Sendable {
    case notify(newUserIds: [UUID])
    case skip(Reason)

    enum Reason: Equatable, Sendable {
        /// You have no active status, so there's nothing to match.
        case noStatus
        /// Everyone nearby was already announced.
        case nothingNew
        /// Less than `minimumInterval` since the last notification; they'll be announced next time.
        case tooSoon
    }
}

/// The rules for nearby notifications:
/// - at most one per `minimumInterval` (an hour);
/// - only when someone new matches; if everyone was already announced, nothing is sent;
/// - changing your activity starts over, since the matches are for a different activity.
nonisolated enum NearbyAlertPolicy {
    static let minimumInterval: TimeInterval = 60 * 60

    static func evaluate(
        state: NearbyAlertState,
        activityId: UUID?,
        matchingUserIds: [UUID],
        now: Date
    ) -> (decision: NearbyAlertDecision, state: NearbyAlertState) {
        var state = rebased(state, on: activityId)
        guard activityId != nil else { return (.skip(.noStatus), state) }

        let newIds = matchingUserIds.filter { !state.announcedUserIds.contains($0) }
        guard !newIds.isEmpty else { return (.skip(.nothingNew), state) }

        if let last = state.lastNotifiedAt, now.timeIntervalSince(last) < minimumInterval {
            // Not marked as announced, so the next allowed check still mentions them.
            return (.skip(.tooSoon), state)
        }

        state.announcedUserIds.formUnion(matchingUserIds)
        state.lastNotifiedAt = now
        return (.notify(newUserIds: newIds), state)
    }

    /// Records people you've seen in the app, so they don't trigger a notification later.
    static func markSeen(state: NearbyAlertState, activityId: UUID?, userIds: [UUID]) -> NearbyAlertState {
        var state = rebased(state, on: activityId)
        if activityId != nil { state.announcedUserIds.formUnion(userIds) }
        return state
    }

    private static func rebased(_ state: NearbyAlertState, on activityId: UUID?) -> NearbyAlertState {
        guard state.activityId != activityId else { return state }
        // Keep lastNotifiedAt: the hourly limit applies across activities.
        return NearbyAlertState(activityId: activityId, announcedUserIds: [], lastNotifiedAt: state.lastNotifiedAt)
    }
}

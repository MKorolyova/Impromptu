//
//  NearbyAlertPolicy.swift
//  Impromptu-app
//

import Foundation

/// What the phone has announced so far for the current activity. Persisted between checks.
nonisolated struct NearbyAlertState: Codable, Equatable, Sendable {
    /// The activity the people below were matched on. A different activity starts over.
    var activityId: UUID?
    /// Everyone you've been told about, or who was already there when you started the activity.
    var announcedUserIds: Set<UUID> = []
    var lastNotifiedAt: Date?
}

nonisolated enum NearbyAlertDecision: Equatable, Sendable {
    case notify(newUserIds: [UUID])
    case skip(Reason)

    enum Reason: Equatable, Sendable {
        /// You have no active status, so there's nothing to match.
        case noStatus
        /// You just started this activity, so the people already doing it aren't news to you.
        case justStarted
        /// Everyone nearby was already announced.
        case nothingNew
        /// Less than `minimumInterval` since the last notification; they'll be announced next time.
        case tooSoon
    }
}

/// The rules for nearby notifications the phone sends itself, which it only does when it can't get the
/// server's push notifications (see `NearbyAlertsService`). Like the server's, they tell you when someone
/// starts doing what you're already doing, not about who was there when you started:
/// - starting an activity (or changing to another) announces nobody; whoever matches then is noted;
/// - after that, only someone new is announced, at most once;
/// - at most one notification per `minimumInterval` (a minute).
nonisolated enum NearbyAlertPolicy {
    static let minimumInterval: TimeInterval = 60

    static func evaluate(
        state: NearbyAlertState,
        activityId: UUID?,
        matchingUserIds: [UUID],
        now: Date
    ) -> (decision: NearbyAlertDecision, state: NearbyAlertState) {
        guard let activityId else { return (.skip(.noStatus), rebased(state, on: nil)) }
        guard state.activityId == activityId else {
            var started = rebased(state, on: activityId)
            started.announcedUserIds = Set(matchingUserIds)
            return (.skip(.justStarted), started)
        }

        var state = state
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

    private static func rebased(_ state: NearbyAlertState, on activityId: UUID?) -> NearbyAlertState {
        guard state.activityId != activityId else { return state }
        // Keep lastNotifiedAt: the time limit applies across activities.
        return NearbyAlertState(activityId: activityId, announcedUserIds: [], lastNotifiedAt: state.lastNotifiedAt)
    }
}

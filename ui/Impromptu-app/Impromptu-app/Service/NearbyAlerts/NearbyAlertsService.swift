//
//  NearbyAlertsService.swift
//  Impromptu-app
//

import BackgroundTasks
import Foundation

struct NearbyEnableOutcome: Equatable {
    var location: LocationAuthorization
    var notificationsAllowed: Bool

    var isEnabled: Bool { location == .always || location == .whileUsing }
}

/// Opt-in "people nearby doing the same thing" alerts.
protocol NearbyAlerting: AnyObject {
    var isEnabled: Bool { get }
    var locationAuthorization: LocationAuthorization { get }
    /// Asks for location and notification permission, then starts reporting your position.
    func enable() async -> NearbyEnableOutcome
    /// Stops reporting and removes your position from the server.
    func disable(userId: UUID?) async
    /// Restarts monitoring at launch, including when iOS relaunches the app for a location change.
    func resume()
    /// For the home screen: reports your position and returns current matches, counting them as seen,
    /// so they won't be announced again. Never notifies.
    func refreshInForeground() async throws -> NearbyResult
    /// For the background refresh: reports your position and notifies if the policy allows.
    func performBackgroundCheck() async
}

final class NearbyAlertsService: NearbyAlerting {
    static let backgroundTaskIdentifier = BackgroundRefresh.taskIdentifier
    /// About a mile.
    static let radiusMeters = 1600

    private let account: AccountServicing
    private let api: NearbyServicing
    private let location: LocationProviding
    private let notifications: NotificationPosting
    private let defaults: UserDefaults
    private let now: () -> Date

    private let enabledKey = "nearbyAlerts.enabled"
    private let stateKey = "nearbyAlerts.state"

    init(
        account: AccountServicing,
        api: NearbyServicing,
        location: LocationProviding,
        notifications: NotificationPosting,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { .now }
    ) {
        self.account = account
        self.api = api
        self.location = location
        self.notifications = notifications
        self.defaults = defaults
        self.now = now
        location.onUpdate = { [weak self] coordinate in
            Task { await self?.check(reporting: coordinate) }
        }
    }

    private(set) var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    private var state: NearbyAlertState {
        get { defaults.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(NearbyAlertState.self, from: $0) } ?? NearbyAlertState() }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: stateKey) }
    }

    var locationAuthorization: LocationAuthorization {
        location.authorization
    }

    func enable() async -> NearbyEnableOutcome {
        let authorization = await location.requestAuthorization()
        let notificationsAllowed = await notifications.requestAuthorization()
        let outcome = NearbyEnableOutcome(location: authorization, notificationsAllowed: notificationsAllowed)
        guard outcome.isEnabled else { return outcome }

        isEnabled = true
        location.startMonitoring()
        scheduleBackgroundCheck()
        return outcome
    }

    func disable(userId: UUID?) async {
        isEnabled = false
        state = NearbyAlertState()
        location.stopMonitoring()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
        if let userId {
            try? await api.stopSharing(for: userId)
        }
    }

    func resume() {
        guard isEnabled, locationAuthorization == .always || locationAuthorization == .whileUsing else { return }
        location.startMonitoring()
        scheduleBackgroundCheck()
    }

    func refreshInForeground() async throws -> NearbyResult {
        guard isEnabled, let userId = account.storedUserId else { return .empty }
        if let coordinate = await location.currentLocation() {
            try? await api.shareLocation(coordinate, for: userId)
        }
        let result = try await api.fetchNearby(for: userId, radiusMeters: Self.radiusMeters)
        state = NearbyAlertPolicy.markSeen(state: state, activityId: result.activity?.id, userIds: result.users.map(\.id))
        return result
    }

    func performBackgroundCheck() async {
        // Book the next run first, so a failed check doesn't end the cycle.
        scheduleBackgroundCheck()
        await check(reporting: await location.currentLocation())
    }

    /// Reports the position, then notifies about new matches if the policy allows.
    private func check(reporting coordinate: Coordinate?) async {
        guard isEnabled, let userId = account.storedUserId else { return }
        if let coordinate {
            try? await api.shareLocation(coordinate, for: userId)
        }
        guard let result = try? await api.fetchNearby(for: userId, radiusMeters: Self.radiusMeters),
              await notifications.isAuthorized() else { return }

        let (decision, newState) = NearbyAlertPolicy.evaluate(
            state: state,
            activityId: result.activity?.id,
            matchingUserIds: result.users.map(\.id),
            now: now()
        )
        state = newState
        guard case .notify(let newIds) = decision, let activity = result.activity else { return }

        let newPeople = result.users.filter { newIds.contains($0.id) }
        let message = NearbyAlertMessage(newPeople: newPeople, totalCount: result.users.count, activityName: activity.name)
        await notifications.post(id: "nearby-\(UUID().uuidString)", title: message.title, body: message.body, route: .nearbyPeople)
    }

    private func scheduleBackgroundCheck() {
        // Submitting without a registered handler raises an uncatchable exception.
        guard BackgroundRefresh.isRegistered else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        // Only the earliest time: iOS decides when it actually runs, usually much later than a minute.
        request.earliestBeginDate = now().addingTimeInterval(NearbyAlertPolicy.minimumInterval)
        // Fails in the simulator and when Background App Refresh is off; significant changes still work.
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// The text of a nearby notification.
struct NearbyAlertMessage: Equatable {
    let title: String
    let body: String

    init(newPeople: [Person], totalCount: Int, activityName: String) {
        let names = newPeople.map(\.displayName)
        let activity = activityName.prefix(1).lowercased() + activityName.dropFirst()
        let isOne = names.count == 1

        title = isOne ? "\(names[0]) is nearby" : "\(names.count) new people nearby"
        let who: String = switch names.count {
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: "\(names[0]), \(names[1]) and \(names.count - 2) more"
        }
        var body = "\(who) \(isOne ? "is" : "are") also \(activity) within a mile."
        if totalCount > names.count {
            body += " \(totalCount) people nearby in all."
        }
        self.body = body
    }
}

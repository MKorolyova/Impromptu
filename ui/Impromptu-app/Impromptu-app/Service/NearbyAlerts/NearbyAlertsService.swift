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

/// Opt-in "people nearby doing the same thing" alerts. The app keeps the server up to date on where you
/// are; the server works out who matches and sends the push notifications (see `PushNotificationService`).
/// On a build that can't get pushes (signed by a free developer team), the phone checks for matches itself
/// and shows the same kind of notification.
protocol NearbyAlerting: AnyObject {
    var isEnabled: Bool { get }
    var locationAuthorization: LocationAuthorization { get }
    /// Asks for location and notification permission, then starts reporting your position.
    func enable() async -> NearbyEnableOutcome
    /// Stops reporting and removes your position from the server.
    func disable(userId: UUID?) async
    /// Restarts monitoring at launch, including when iOS relaunches the app for a location change.
    func resume()
    /// For the home screen: reports your position and returns current matches. Without push, also
    /// notifies about new ones, so they pop up while the app is open too.
    func refreshInForeground() async throws -> NearbyResult
    /// For the background refresh: reports your position, so the server can tell you and others about
    /// matches. Without push, checks for them and notifies itself.
    func performBackgroundCheck() async
}

final class NearbyAlertsService: NearbyAlerting {
    static let backgroundTaskIdentifier = BackgroundRefresh.taskIdentifier
    /// 3 miles, the same as the server uses for push alerts and note requests.
    static let radiusMeters = 4828
    /// The earliest the next background refresh may run.
    static let backgroundRefreshInterval: TimeInterval = 60

    private let account: AccountServicing
    private let api: NearbyServicing
    private let location: LocationProviding
    private let notifications: NotificationPosting
    private let push: PushRegistering
    private let defaults: UserDefaults
    private let now: () -> Date

    private let enabledKey = "nearbyAlerts.enabled"
    private let stateKey = "nearbyAlerts.state"

    init(
        account: AccountServicing,
        api: NearbyServicing,
        location: LocationProviding,
        notifications: NotificationPosting,
        push: PushRegistering,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { .now }
    ) {
        self.account = account
        self.api = api
        self.location = location
        self.notifications = notifications
        self.push = push
        self.defaults = defaults
        self.now = now
        location.onUpdate = { [weak self] coordinate in
            Task { await self?.report(coordinate) }
        }
    }

    private(set) var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    /// Who the phone has already announced, for when it sends the notifications itself.
    private var state: NearbyAlertState {
        get { defaults.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(NearbyAlertState.self, from: $0) } ?? NearbyAlertState() }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: stateKey) }
    }

    var locationAuthorization: LocationAuthorization {
        location.authorization
    }

    func enable() async -> NearbyEnableOutcome {
        let authorization = await location.requestAuthorization()
        // Whether the server or the phone sends the alerts, iOS only shows them with this permission.
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
        await notifyFromPhoneIfNeeded(about: result)
        return result
    }

    func performBackgroundCheck() async {
        // Book the next run first, so a failed check doesn't end the cycle.
        scheduleBackgroundCheck()
        await report(await location.currentLocation())
    }

    /// Keeps the server's copy of your position fresh; positions over 2 hours old don't count as nearby.
    /// The server sends any alerts the new position brings, unless this device can't get them.
    private func report(_ coordinate: Coordinate?) async {
        guard isEnabled, let userId = account.storedUserId else { return }
        if let coordinate {
            try? await api.shareLocation(coordinate, for: userId)
        }
        guard !push.isAvailable,
              let result = try? await api.fetchNearby(for: userId, radiusMeters: Self.radiusMeters) else { return }
        await notifyFromPhoneIfNeeded(about: result)
    }

    /// Only when this device can't get the server's pushes: shows a regular notification about new
    /// matches, following `NearbyAlertPolicy`. With push, the server has already sent one.
    private func notifyFromPhoneIfNeeded(about result: NearbyResult) async {
        guard !push.isAvailable, await notifications.isAuthorized() else { return }
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
        request.earliestBeginDate = now().addingTimeInterval(Self.backgroundRefreshInterval)
        // Fails in the simulator and when Background App Refresh is off; significant changes still work.
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// The text of a nearby notification the phone sends itself; the same wording as the server's pushes.
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
        var body = "\(who) \(isOne ? "is" : "are") also \(activity) within 3 miles."
        if totalCount > names.count {
            body += " \(totalCount) people nearby in all."
        }
        self.body = body
    }
}

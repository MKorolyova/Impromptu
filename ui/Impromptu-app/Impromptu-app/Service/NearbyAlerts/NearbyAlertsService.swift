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
protocol NearbyAlerting: AnyObject {
    var isEnabled: Bool { get }
    var locationAuthorization: LocationAuthorization { get }
    /// Asks for location and notification permission, then starts reporting your position.
    func enable() async -> NearbyEnableOutcome
    /// Stops reporting and removes your position from the server.
    func disable(userId: UUID?) async
    /// Restarts monitoring at launch, including when iOS relaunches the app for a location change.
    func resume()
    /// For the home screen: reports your position and returns current matches.
    func refreshInForeground() async throws -> NearbyResult
    /// For the background refresh: reports your position, so the server can tell you and others about matches.
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
    private let defaults: UserDefaults

    private let enabledKey = "nearbyAlerts.enabled"

    init(
        account: AccountServicing,
        api: NearbyServicing,
        location: LocationProviding,
        notifications: NotificationPosting,
        defaults: UserDefaults = .standard
    ) {
        self.account = account
        self.api = api
        self.location = location
        self.notifications = notifications
        self.defaults = defaults
        location.onUpdate = { [weak self] coordinate in
            Task { await self?.report(coordinate) }
        }
    }

    private(set) var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    var locationAuthorization: LocationAuthorization {
        location.authorization
    }

    func enable() async -> NearbyEnableOutcome {
        let authorization = await location.requestAuthorization()
        // The alerts themselves come from the server, but iOS only shows them with this permission.
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
        return try await api.fetchNearby(for: userId, radiusMeters: Self.radiusMeters)
    }

    func performBackgroundCheck() async {
        // Book the next run first, so a failed check doesn't end the cycle.
        scheduleBackgroundCheck()
        if let coordinate = await location.currentLocation() {
            await report(coordinate)
        }
    }

    /// Keeps the server's copy of your position fresh; positions over 2 hours old don't count as nearby.
    /// The server sends any alerts the new position brings.
    private func report(_ coordinate: Coordinate) async {
        guard isEnabled, let userId = account.storedUserId else { return }
        try? await api.shareLocation(coordinate, for: userId)
    }

    private func scheduleBackgroundCheck() {
        // Submitting without a registered handler raises an uncatchable exception.
        guard BackgroundRefresh.isRegistered else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        // Only the earliest time: iOS decides when it actually runs, usually much later than a minute.
        request.earliestBeginDate = .now.addingTimeInterval(Self.backgroundRefreshInterval)
        // Fails in the simulator and when Background App Refresh is off; significant changes still work.
        try? BGTaskScheduler.shared.submit(request)
    }
}

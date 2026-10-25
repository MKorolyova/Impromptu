//
//  Services.swift
//  Impromptu-app
//

import SwiftUI

/// Dependency container handed to view models. Swap `.live` for `.mock` to run
/// without a backend.
struct Services {
    let account: AccountServicing
    let activities: ActivityServicing
    let statuses: StatusServicing
    let people: PeopleServicing
    let nearbyAlerts: NearbyAlerting
    let noteRequests: NoteRequestServicing
    let noteMonitor: NoteRequestMonitoring
    /// Shared by nearby alerts and note replies, so there's one CLLocationManager.
    let location: LocationProviding
    let router: AppRouter
    let widgets: WidgetSyncing

    static func live() -> Services {
        let client = URLSessionAPIClient()
        let account = AccountService(client: client)
        let router = AppRouter()
        let location = CoreLocationProvider()
        let notifications = LocalNotificationService(router: router)
        let noteRequests = NoteRequestService(client: client)
        return Services(
            account: account,
            activities: ActivityService(client: client),
            statuses: StatusService(client: client),
            people: PeopleService(client: client),
            nearbyAlerts: NearbyAlertsService(
                account: account,
                api: NearbyService(client: client),
                location: location,
                notifications: notifications
            ),
            noteRequests: noteRequests,
            noteMonitor: NoteRequestMonitor(account: account, api: noteRequests, notifications: notifications),
            location: location,
            router: router,
            widgets: WidgetSyncService()
        )
    }

    static func mock(signedIn: Bool = true) -> Services {
        let noteRequests = MockNoteRequestService()
        return Services(
            account: MockAccountService(signedIn: signedIn),
            activities: MockActivityService(),
            statuses: MockStatusService(),
            people: MockPeopleService(),
            nearbyAlerts: MockNearbyAlerts(),
            noteRequests: noteRequests,
            noteMonitor: MockNoteRequestMonitor(service: noteRequests),
            location: MockLocationProvider(),
            router: AppRouter(),
            widgets: MockWidgetSyncService()
        )
    }
}

extension EnvironmentValues {
    /// Defaults to mocks so previews work without any setup.
    @Entry var services: Services = .mock()
}

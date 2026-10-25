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
    let widgets: WidgetSyncing

    static func live() -> Services {
        let client = URLSessionAPIClient()
        let account = AccountService(client: client)
        return Services(
            account: account,
            activities: ActivityService(client: client),
            statuses: StatusService(client: client),
            people: PeopleService(client: client),
            nearbyAlerts: NearbyAlertsService(
                account: account,
                api: NearbyService(client: client),
                location: CoreLocationProvider(),
                notifications: LocalNotificationService()
            ),
            widgets: WidgetSyncService()
        )
    }

    static func mock(signedIn: Bool = true) -> Services {
        Services(
            account: MockAccountService(signedIn: signedIn),
            activities: MockActivityService(),
            statuses: MockStatusService(),
            people: MockPeopleService(),
            nearbyAlerts: MockNearbyAlerts(),
            widgets: MockWidgetSyncService()
        )
    }
}

extension EnvironmentValues {
    /// Defaults to mocks so previews work without any setup.
    @Entry var services: Services = .mock()
}

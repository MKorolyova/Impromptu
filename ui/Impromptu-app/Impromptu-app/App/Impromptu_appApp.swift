//
//  Impromptu_appApp.swift
//  Impromptu-app
//
//  Created by Alekzander Brysch on 10/24/26.
//

import SwiftUI

@main
struct Impromptu_appApp: App {
    private let services: Services
    @State private var session: SessionViewModel

    init() {
        let services = Services.live()
        self.services = services
        _session = State(initialValue: SessionViewModel(services: services))
        // Must run at launch: iOS relaunches the app in the background for location changes,
        // and only delivers them once monitoring has restarted.
        services.nearbyAlerts.resume()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.services, services)
                .environment(session)
        }
        .backgroundTask(.appRefresh(NearbyAlertsService.backgroundTaskIdentifier)) { [nearbyAlerts = services.nearbyAlerts] in
            await nearbyAlerts.performBackgroundCheck()
        }
    }
}

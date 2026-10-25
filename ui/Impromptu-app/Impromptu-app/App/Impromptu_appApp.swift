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
    /// Toggled from the profile menu; nil follows the system.
    @AppStorage(AppTheme.storageKey, store: AppTheme.store) private var theme: AppTheme = .system

    init() {
        let services = Services.live()
        self.services = services
        _session = State(initialValue: SessionViewModel(services: services))
        // Register before resume(), which schedules the next refresh.
        BackgroundRefresh.register { [nearbyAlerts = services.nearbyAlerts, noteMonitor = services.noteMonitor] in
            await nearbyAlerts.performBackgroundCheck()
            // Also the only chance to hear about note requests and replies while the app is closed.
            _ = try? await noteMonitor.poll(notify: true)
        }
        // Must run at launch: iOS relaunches the app in the background for location changes,
        // and only delivers them once monitoring has restarted.
        services.nearbyAlerts.resume()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.services, services)
                .environment(session)
                .preferredColorScheme(theme.colorScheme)
        }
    }
}

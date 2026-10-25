//
//  AppDelegate.swift
//  Impromptu-app
//

import UIKit

/// UIKit only hands the APNs device token to an app delegate, so this one exists to pass it on.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by the app once its services exist. A token that arrives before then waits.
    var push: PushRegistering? {
        didSet { deliverPendingToken() }
    }

    private var pendingToken: Data?

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        pendingToken = deviceToken
        deliverPendingToken()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Usually a build signed by a free developer team, which can't have the Push Notifications
        // capability. The phone then sends nearby alerts itself.
        print("AppDelegate: couldn't register for push notifications: \(error.localizedDescription)")
        push?.didFailToRegister()
    }

    private func deliverPendingToken() {
        guard let push, let token = pendingToken else { return }
        pendingToken = nil
        Task { await push.didReceiveDeviceToken(token) }
    }
}

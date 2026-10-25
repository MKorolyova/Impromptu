//
//  PushNotificationService.swift
//  Impromptu-app
//

import Foundation
import UIKit

/// Push notifications sent by the server, like "Sam is nearby". iOS gives the device token to the
/// app delegate, which passes it here to be registered for whoever is signed in. Showing them and
/// handling taps is `LocalNotificationService`'s job, the same as for local ones.
protocol PushRegistering: AnyObject {
    /// Whether iOS gave this device a push token, as of the last time it was asked. False on builds signed by
    /// a free (personal) developer team, which can't use push; the phone then sends nearby alerts itself.
    var isAvailable: Bool { get }
    /// Asks iOS for this device's token. Call whenever someone is signed in: at launch and after signing in.
    func register()
    /// From the app delegate. Registers the token with the server for the signed-in user.
    func didReceiveDeviceToken(_ deviceToken: Data) async
    /// From the app delegate, when iOS won't give this build a token.
    func didFailToRegister()
    /// Stops pushes to this device for the user who's signing out.
    func unregister(userId: UUID) async
}

final class PushNotificationService: PushRegistering {
    private let account: AccountServicing
    private let client: APIClient
    private let requestToken: () -> Void
    private let defaults: UserDefaults
    /// Hex, as APNs and the API spell it. Nil until iOS hands it over this launch.
    private(set) var deviceToken: String?

    /// Remembered, so a background launch knows before iOS has answered again.
    private let availableKey = "push.isAvailable"

    init(
        account: AccountServicing,
        client: APIClient,
        defaults: UserDefaults = .standard,
        requestToken: @escaping () -> Void = { UIApplication.shared.registerForRemoteNotifications() }
    ) {
        self.account = account
        self.client = client
        self.defaults = defaults
        self.requestToken = requestToken
    }

    private(set) var isAvailable: Bool {
        get { defaults.bool(forKey: availableKey) }
        set { defaults.set(newValue, forKey: availableKey) }
    }

    func register() {
        requestToken()
    }

    func didReceiveDeviceToken(_ deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        self.deviceToken = token
        isAvailable = true
        guard let userId = account.storedUserId else { return }
        // If this fails, the next launch registers again.
        try? await client.send(.saveDeviceToken(SaveDeviceTokenRequest(token: token, environment: .current), for: userId))
    }

    func didFailToRegister() {
        isAvailable = false
    }

    func unregister(userId: UUID) async {
        guard let deviceToken else { return }
        try? await client.send(.deleteDeviceToken(DeleteDeviceTokenRequest(token: deviceToken), for: userId))
    }
}

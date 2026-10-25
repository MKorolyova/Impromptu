//
//  SessionViewModel.swift
//  Impromptu-app
//

import Foundation
import Observation

/// App-wide account state. Owned by the app root and shared via the environment.
@Observable
final class SessionViewModel {
    enum State: Equatable {
        case restoring
        case restoreFailed(String)
        case signedOut
        case signedIn(User)
    }

    private(set) var state: State = .restoring

    private let account: AccountServicing
    private let widgets: WidgetSyncing
    private let nearbyAlerts: NearbyAlerting
    private let noteMonitor: NoteRequestMonitoring
    private let push: PushRegistering

    init(services: Services) {
        account = services.account
        widgets = services.widgets
        nearbyAlerts = services.nearbyAlerts
        noteMonitor = services.noteMonitor
        push = services.push
    }

    var user: User? {
        if case .signedIn(let user) = state { user } else { nil }
    }

    /// Reloads the remembered user on launch.
    func restore() async {
        guard let userId = account.storedUserId else {
            state = .signedOut
            return
        }
        state = .restoring
        do {
            signIn(try await account.restoreUser(userId))
        } catch let error as APIError where error.code == .notFound {
            // The account was deleted; forget it.
            signOut()
        } catch {
            // Keep the stored ID so a retry can succeed once the server is reachable.
            state = .restoreFailed(error.localizedDescription)
        }
    }

    func logIn(email: String, password: String) async throws {
        signIn(try await account.logIn(email: email, password: password))
    }

    /// Sign-up creates the account partway through and keeps its sheet up until the last step,
    /// then hands over here to open the home screen.
    func completeRegistration(_ user: User) {
        signIn(user)
    }

    /// Also asks for this device's push token, so the server can send nearby alerts to this user.
    private func signIn(_ user: User) {
        state = .signedIn(user)
        push.register()
    }

    /// After a profile edit, so every screen shows the new name.
    func updateUser(_ user: User) {
        guard case .signedIn(let current) = state, current.id == user.id else { return }
        state = .signedIn(user)
    }

    func signOut() {
        // Capture the ID first: stopping location sharing on the server needs it after sign-out clears it.
        let userId = account.storedUserId
        let nearbyAlerts = nearbyAlerts
        let push = push
        Task {
            await nearbyAlerts.disable(userId: userId)
            if let userId { await push.unregister(userId: userId) }
        }
        account.signOut()
        noteMonitor.reset()
        widgets.clear()
        state = .signedOut
    }

    func deleteAccount() async throws {
        guard let user else { return }
        try await account.deleteAccount(user.id)
        signOut()
    }
}

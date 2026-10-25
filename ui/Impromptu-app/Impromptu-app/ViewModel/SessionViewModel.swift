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

    init(services: Services) {
        account = services.account
        widgets = services.widgets
        nearbyAlerts = services.nearbyAlerts
        noteMonitor = services.noteMonitor
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
            state = .signedIn(try await account.restoreUser(userId))
        } catch let error as APIError where error.code == .notFound {
            // The account was deleted; forget it.
            signOut()
        } catch {
            // Keep the stored ID so a retry can succeed once the server is reachable.
            state = .restoreFailed(error.localizedDescription)
        }
    }

    func logIn(email: String, password: String) async throws {
        state = .signedIn(try await account.logIn(email: email, password: password))
    }

    func createAccount(_ request: CreateUserRequest) async throws {
        state = .signedIn(try await account.createAccount(request))
    }

    func signOut() {
        // Capture the ID first: stopping location sharing on the server needs it after sign-out clears it.
        let userId = account.storedUserId
        let nearbyAlerts = nearbyAlerts
        Task { await nearbyAlerts.disable(userId: userId) }
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

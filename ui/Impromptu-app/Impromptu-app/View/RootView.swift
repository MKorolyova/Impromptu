//
//  RootView.swift
//  Impromptu-app
//

import SwiftUI

struct RootView: View {
    @Environment(SessionViewModel.self) private var session
    @Environment(\.services) private var services

    var body: some View {
        switch session.state {
        case .restoring:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
                .task { await session.restore() }
        case .restoreFailed(let message):
            ContentUnavailableView {
                Label("Can't reach Impromptu", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await session.restore() } }
                Button("Sign Out", role: .destructive, action: session.signOut)
            }
        case .signedOut:
            WelcomeView()
        case .signedIn(let user):
            HomeView(user: user, services: services)
                .id(user.id)
        }
    }
}

#Preview {
    RootView()
        .environment(SessionViewModel(services: .mock()))
}

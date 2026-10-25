//
//  HomeView.swift
//  Impromptu-app
//

import SwiftUI

/// The feed: you and your status composer on top, then what your friends are up to, then everyone else.
struct HomeView: View {
    private enum Sheet: Identifiable {
        case activities
        case nearbyPeople
        case notes
        case addFriend

        var id: Self { self }
    }

    @Environment(SessionViewModel.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(AppTheme.storageKey, store: AppTheme.store) private var theme: AppTheme = .system
    @State private var viewModel: HomeViewModel
    @State private var sheet: Sheet?
    @State private var isShowingSettings = false
    private let user: User
    private let services: Services

    private static let refreshInterval: Duration = .seconds(10)

    init(user: User, services: Services) {
        _viewModel = State(initialValue: HomeViewModel(user: user, services: services))
        self.user = user
        self.services = services
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    MyStatusCard(viewModel: viewModel) { sheet = .activities }
                        .padding(.bottom, 8)
                    if viewModel.loadState == .loaded {
                        SectionHeader(title: "Nearby", count: viewModel.nearby?.users.count)
                        NearbySection(viewModel: viewModel) { sheet = .nearbyPeople }
                            .padding(.bottom, 8)
                    }
                    feed
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color.appBackground)
            .navigationTitle(Brand.appName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    addFriendButton
                }
                ToolbarItem(placement: .topBarTrailing) {
                    profileMenu
                }
            }
            .navigationDestination(isPresented: $isShowingSettings) {
                SettingsView(user: viewModel.user, services: services)
            }
            // Settings can rename you.
            .onChange(of: user) { _, user in viewModel.userDidChange(user) }
            .refreshable { await viewModel.load() }
            .task {
                await viewModel.load()
                // Keep the feed fresh while it's on screen; cancelled when the view goes away.
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.refreshInterval)
                    await viewModel.load()
                }
            }
            .sheet(item: $sheet, onDismiss: refreshAfterSheet) { sheet in
                switch sheet {
                case .activities:
                    ActivityPickerView(viewModel: viewModel)
                case .nearbyPeople:
                    NearbyPeopleView(user: viewModel.user, services: services) { self.sheet = .notes }
                case .notes:
                    NotesInboxView(user: viewModel.user, services: services)
                case .addFriend:
                    AddFriendNearbyView(user: viewModel.user, services: services)
                }
            }
            // A tapped notification, including one that launched the app before this view existed.
            .onChange(of: services.router.pendingRoute, initial: true) { _, route in
                guard let route else { return }
                services.router.pendingRoute = nil
                sheet = switch route {
                case .nearbyPeople: .nearbyPeople
                case .notes: .notes
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var feed: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load the feed", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await viewModel.load() } }
            }
        case .loaded:
            if viewModel.people.isEmpty {
                ContentUnavailableView {
                    Label("No one else is here yet", systemImage: "person.2")
                } description: {
                    Text("Add a friend to see what they're up to.")
                } actions: {
                    Button("Add Friend", systemImage: "person.badge.plus") { sheet = .addFriend }
                        .buttonStyle(.brand(.primary, compact: true))
                }
            } else {
                SectionHeader(title: "Happening now",
                              count: viewModel.friendsHappening.isEmpty ? nil : viewModel.friendsHappening.count)
                if viewModel.friendsHappening.isEmpty {
                    noFriendsHappening
                } else {
                    ForEach(viewModel.friendsHappening) { person in
                        if let status = person.activeStatus {
                            PersonCard(person: person, status: status)
                        }
                    }
                }
                peopleList("Friends", viewModel.quietFriends)
                peopleList("Everyone else", viewModel.everyoneElse)
            }
        }
    }

    /// "Happening now" is friends only; until there are some, say so and offer to add one.
    private var noFriendsHappening: some View {
        let hasFriends = !viewModel.friendIds.isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            Text(hasFriends ? "None of your friends have a status right now." : "Add friends to see what they're up to here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !hasFriends {
                Button("Add Friend", systemImage: "person.badge.plus") { sheet = .addFriend }
                    .buttonStyle(.brand(.secondary, compact: true))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    @ViewBuilder
    private func peopleList(_ title: String, _ people: [Person]) -> some View {
        if !people.isEmpty {
            SectionHeader(title: title, count: people.count)
                .padding(.top, 8)
            VStack(spacing: 0) {
                ForEach(people) { person in
                    PersonRow(person: person)
                    if person.id != people.last?.id {
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .cardBackground()
        }
    }

    private var addFriendButton: some View {
        Button {
            sheet = .addFriend
        } label: {
            Label("Add Friend", systemImage: "person.badge.plus")
        }
    }

    /// A sheet may have added a friend or changed requests and replies.
    private func refreshAfterSheet() {
        Task { await viewModel.load() }
    }

    /// Top right: notes, settings, light/dark, and log out. A red dot while note requests are waiting.
    private var profileMenu: some View {
        let waiting = viewModel.openNoteRequestCount
        return Menu {
            Section(viewModel.user.email) {
                Button(waiting > 0 ? "Notes (\(waiting) waiting)" : "Notes", systemImage: waiting > 0 ? "tray.full" : "tray") {
                    sheet = .notes
                }
                Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                Button(isDark ? "Light Mode" : "Dark Mode", systemImage: isDark ? "sun.max" : "moon", action: toggleTheme)
            }
            Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right", action: session.signOut)
        } label: {
            AvatarView(id: viewModel.user.id, firstName: viewModel.user.firstName, lastName: viewModel.user.lastName,
                       size: 32, usesBrandColors: true)
                .overlay(alignment: .topTrailing) {
                    if waiting > 0 {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 1.5))
                            .offset(x: 2, y: -2)
                    }
                }
        }
        .accessibilityLabel("Profile")
        .accessibilityValue(waiting > 0 ? "\(waiting) note requests waiting" : "")
    }

    private var isDark: Bool { colorScheme == .dark }

    private func toggleTheme() {
        theme = isDark ? .light : .dark
        viewModel.appearanceDidChange()
    }
}

private struct SectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.bold())
            if let count {
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    HomeView(user: SampleData.user, services: .mock())
        .environment(SessionViewModel(services: .mock()))
}

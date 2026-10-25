//
//  HomeView.swift
//  Impromptu-app
//

import SwiftUI

/// The feed: you and your status composer on top, then everyone else's statuses.
struct HomeView: View {
    private enum Sheet: Identifiable {
        case activities
        case nearbyPeople
        case notes

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

    private static let refreshInterval: Duration = .seconds(60)

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
                    notesButton
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
                    ActivityPickerView(
                        activities: viewModel.activities,
                        selected: viewModel.draft.activity,
                        onSelect: { viewModel.draft.activity = $0 },
                        onCreate: { name, minutes in
                            await viewModel.createActivity(name: name, durationMinutes: minutes)
                        },
                        onDelete: { activity in
                            Task { await viewModel.deleteActivity(activity) }
                        }
                    )
                case .nearbyPeople:
                    NearbyPeopleView(user: viewModel.user, services: services) { self.sheet = .notes }
                case .notes:
                    NotesInboxView(user: viewModel.user, services: services)
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
                ContentUnavailableView("No one else is here yet", systemImage: "person.2",
                                       description: Text("Invite friends to see what they're up to."))
            } else {
                if !viewModel.activePeople.isEmpty {
                    SectionHeader(title: "Happening now", count: viewModel.activePeople.count)
                    ForEach(viewModel.activePeople) { person in
                        if let status = person.activeStatus {
                            PersonCard(person: person, status: status)
                        }
                    }
                }
                if !viewModel.idlePeople.isEmpty {
                    SectionHeader(title: "Everyone else", count: viewModel.idlePeople.count)
                        .padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(viewModel.idlePeople) { person in
                            IdlePersonRow(person: person)
                            if person.id != viewModel.idlePeople.last?.id {
                                Divider().padding(.leading, 48)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .cardBackground()
                }
            }
        }
    }

    private var notesButton: some View {
        Button {
            sheet = .notes
        } label: {
            Label("Notes", systemImage: viewModel.openNoteRequestCount > 0 ? "tray.full.fill" : "tray")
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.openNoteRequestCount > 0 {
                Text("\(viewModel.openNoteRequestCount)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.red, in: Capsule())
                    .offset(x: 8, y: -6)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityValue(viewModel.openNoteRequestCount > 0 ? "\(viewModel.openNoteRequestCount) waiting" : "")
    }

    /// Requests and replies may have changed while a sheet was up.
    private func refreshAfterSheet() {
        Task {
            await viewModel.refreshNotes()
            await viewModel.refreshNearby()
        }
    }

    /// Top right: settings, light/dark, and log out.
    private var profileMenu: some View {
        Menu {
            Section(viewModel.user.email) {
                Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                Button(isDark ? "Light Mode" : "Dark Mode", systemImage: isDark ? "sun.max" : "moon", action: toggleTheme)
            }
            Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right", action: session.signOut)
        } label: {
            AvatarView(id: viewModel.user.id, firstName: viewModel.user.firstName, lastName: viewModel.user.lastName,
                       size: 32, usesBrandColors: true)
        }
        .accessibilityLabel("Profile")
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

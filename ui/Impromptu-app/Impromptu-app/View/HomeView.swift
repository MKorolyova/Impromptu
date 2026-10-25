//
//  HomeView.swift
//  Impromptu-app
//

import SwiftUI

/// The feed: your account and status drop-down on top, then everyone else's statuses.
struct HomeView: View {
    @Environment(SessionViewModel.self) private var session
    @State private var viewModel: HomeViewModel
    @State private var isBrowsingActivities = false
    @State private var isConfirmingDelete = false

    private static let refreshInterval: Duration = .seconds(60)

    init(user: User, services: Services) {
        _viewModel = State(initialValue: HomeViewModel(user: user, services: services))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    MyStatusCard(viewModel: viewModel) { isBrowsingActivities = true }
                        .padding(.bottom, 8)
                    if viewModel.loadState == .loaded {
                        SectionHeader(title: "Nearby", count: viewModel.nearby?.users.count)
                        NearbySection(viewModel: viewModel)
                            .padding(.bottom, 8)
                    }
                    feed
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color.feedBackground)
            .navigationTitle("Impromptu")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    accountMenu
                }
            }
            .refreshable { await viewModel.load() }
            .task {
                await viewModel.load()
                // Keep the feed fresh while it's on screen; cancelled when the view goes away.
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.refreshInterval)
                    await viewModel.load()
                }
            }
            .sheet(isPresented: $isBrowsingActivities) {
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
            }
            .confirmationDialog("Delete your account?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Account", role: .destructive) {
                    Task {
                        do {
                            try await session.deleteAccount()
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                        }
                    }
                }
            } message: {
                Text("Your statuses and custom activities will no longer be visible.")
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

    private var accountMenu: some View {
        Menu {
            Section(viewModel.user.email) {
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", action: session.signOut)
            }
            Button("Delete Account", systemImage: "trash", role: .destructive) {
                isConfirmingDelete = true
            }
        } label: {
            Label("Account", systemImage: "person.crop.circle")
        }
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

//
//  SettingsView.swift
//  Impromptu-app
//

import SwiftUI

/// Pushed from the profile menu.
struct SettingsView: View {
    @Environment(SessionViewModel.self) private var session
    @State private var viewModel: SettingsViewModel
    @State private var isConfirmingDelete = false

    init(user: User, services: Services) {
        _viewModel = State(initialValue: SettingsViewModel(user: user, services: services))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                profileCard
                ForEach(SettingsViewModel.Audience.allCases) { audience in
                    AudienceCard(audience: audience, viewModel: viewModel)
                }
                statusSourcesCard
                accountCard
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBackground)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadFriends() }
        .sheet(item: $viewModel.addingTo) { audience in
            AddFriendSheet(audience: audience, viewModel: viewModel)
        }
        .confirmationDialog("Delete your account?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) {
                Task { await viewModel.deleteAccount(session: session) }
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

    // MARK: Profile

    private var profileCard: some View {
        SettingsCard(title: "Profile", footer: "Friends see your nickname if you have one, otherwise your full name.") {
            HStack(spacing: 14) {
                AvatarView(id: viewModel.user.id, firstName: viewModel.firstName, lastName: viewModel.lastName,
                           size: 52, usesBrandColors: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(previewName)
                        .font(.headline)
                    Text(viewModel.user.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            TextField("First name", text: $viewModel.firstName)
                .textContentType(.givenName)
                .brandField()
            TextField("Last name", text: $viewModel.lastName)
                .textContentType(.familyName)
                .brandField()
            TextField("Nickname (optional)", text: $viewModel.nickname)
                .textContentType(.nickname)
                .brandField()

            if viewModel.showsProfileSaved {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.brandAccent)
                    .frame(maxWidth: .infinity)
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { viewModel.dismissProfileSaved() }
                    }
            } else {
                Button {
                    Task { await viewModel.saveProfile(session: session) }
                } label: {
                    if viewModel.isSavingProfile {
                        ProgressView()
                            .tint(Color.onBrandAccent)
                    } else {
                        Text("Save Changes")
                    }
                }
                .buttonStyle(.brand)
                .disabled(!viewModel.canSaveProfile)
            }
        }
    }

    private var previewName: String {
        let nickname = viewModel.nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return nickname.isEmpty ? "\(viewModel.firstName) \(viewModel.lastName)" : nickname
    }

    // MARK: Status updates

    private var statusSourcesCard: some View {
        SettingsCard(title: "Status updates", footer: "Saved on this iPhone.") {
            ForEach(StatusSource.allCases) { source in
                StatusSourceRow(source: source, isOn: Binding(
                    get: { viewModel.statusSources.contains(source) },
                    set: { viewModel.setStatusSource(source, isOn: $0) }
                ))
            }
        }
    }

    // MARK: Account

    private var accountCard: some View {
        SettingsCard(title: "Account") {
            Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right", action: session.signOut)
                .buttonStyle(.brand(.secondary))
            Button("Delete Account", systemImage: "trash", role: .destructive) {
                isConfirmingDelete = true
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}

/// "Who can see your location" or "…your notes": the friends on it, and a way to add more.
private struct AudienceCard: View {
    let audience: SettingsViewModel.Audience
    let viewModel: SettingsViewModel

    var body: some View {
        SettingsCard(title: audience.title, footer: audience.explanation) {
            if let error = viewModel.friendsLoadError {
                InlineError(message: error)
                Button("Try Again") { Task { await viewModel.loadFriends() } }
                    .buttonStyle(.brand(.secondary, compact: true))
            } else if !viewModel.hasLoadedFriends {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                let members = viewModel.friends(in: audience)
                if members.isEmpty {
                    Text("No one yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(members) { friend in
                            FriendRow(friend: friend) {
                                Button {
                                    Task { await viewModel.remove(friend, from: audience) }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Stop sharing with \(friend.displayName)")
                            }
                            if friend.id != members.last?.id {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .insetBackground()
                }
            }

            Button("Add Friend", systemImage: "person.badge.plus") {
                viewModel.startAdding(to: audience)
            }
            .buttonStyle(.brand(.secondary))
        }
    }
}

/// Add someone by email, or pick from your other friends.
private struct AddFriendSheet: View {
    let audience: SettingsViewModel.Audience
    @Bindable var viewModel: SettingsViewModel
    @FocusState private var isEmailFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SheetHeader(title: audience.addTitle, subtitle: "Add a friend by the email they use on \(Brand.appName).")

                VStack(alignment: .leading, spacing: 12) {
                    TextField("Friend's email", text: $viewModel.friendEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($isEmailFocused)
                        .onSubmit(add)
                        .brandField()
                    if let error = viewModel.addFriendError {
                        InlineError(message: error)
                    }
                    Button(action: add) {
                        if viewModel.isAddingFriend {
                            ProgressView()
                                .tint(Color.onBrandAccent)
                        } else {
                            Text("Add")
                        }
                    }
                    .buttonStyle(.brand)
                    .disabled(!viewModel.canAddFriendByEmail)
                }

                let others = viewModel.friends(notIn: audience)
                if !others.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your other friends")
                            .font(.headline)
                        VStack(spacing: 0) {
                            ForEach(others) { friend in
                                FriendRow(friend: friend) {
                                    Button("Add") {
                                        Task { await viewModel.add(friend, to: audience) }
                                    }
                                    .buttonStyle(.brand(.secondary, compact: true))
                                }
                                if friend.id != others.last?.id {
                                    Divider().padding(.leading, 52)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .insetBackground()
                    }
                }
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .brandSheet()
        .onAppear { isEmailFocused = true }
    }

    private func add() {
        Task { await viewModel.addFriendByEmail() }
    }
}

private struct FriendRow<Trailing: View>: View {
    let friend: Friend
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(id: friend.id, firstName: friend.firstName, lastName: friend.lastName, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.body.weight(.medium))
                if friend.nickname != nil {
                    Text("\(friend.firstName) \(friend.lastName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.vertical, 10)
    }
}

/// A titled card with an optional footnote, for each settings section.
private struct SettingsCard<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            content()
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

private extension SettingsViewModel.Audience {
    var title: String {
        switch self {
        case .location: "Who can see your location"
        case .notes: "Who can see your notes"
        }
    }

    var explanation: String {
        switch self {
        case .location: "Only friends on this list can see where you are."
        case .notes: "Only friends on this list can see the note on your status."
        }
    }

    var addTitle: String {
        switch self {
        case .location: "Share your location"
        case .notes: "Share your notes"
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(user: SampleData.user, services: .mock())
    }
    .environment(SessionViewModel(services: .mock()))
}

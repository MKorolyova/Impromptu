//
//  NearbyPeopleView.swift
//  Impromptu-app
//

import SwiftUI

/// Opened from a nearby notification or the home screen: pick people close by and ask them for a note.
struct NearbyPeopleView: View {
    @State private var viewModel: NearbyPeopleViewModel
    @Environment(\.dismiss) private var dismiss
    /// Opens the inbox, e.g. after sending, to wait for replies.
    let onShowNotes: () -> Void

    init(user: User, services: Services, onShowNotes: @escaping () -> Void) {
        _viewModel = State(initialValue: NearbyPeopleViewModel(user: user, services: services))
        self.onShowNotes = onShowNotes
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Nearby")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    if viewModel.loadState == .loaded, !viewModel.people.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Closest \(NearbyPeopleViewModel.quickPickCount)", action: viewModel.selectClosest)
                        }
                    }
                }
                .refreshable { await viewModel.load() }
                .task { await viewModel.load() }
                .alert("Couldn't send", isPresented: Binding(
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
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            ProgressView()
        case .alertsOff:
            ContentUnavailableView("Nearby alerts are off", systemImage: "location.slash",
                                   description: Text("Turn on Nearby alerts on the home screen to see who's around."))
        case .noStatus:
            ContentUnavailableView("Set a status first", systemImage: "sparkles",
                                   description: Text("You'll see people nearby doing the same thing."))
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") { Task { await viewModel.load() } }
            }
        case .loaded:
            if viewModel.people.isEmpty {
                ContentUnavailableView("No one nearby right now", systemImage: "location.circle",
                                       description: Text(activityLine.map { "No one within 3 miles is \($0)." } ?? ""))
            } else {
                peopleList
            }
        }
    }

    private var peopleList: some View {
        List {
            Section {
                ForEach(viewModel.people) { person in
                    NearbyPersonRow(
                        person: person,
                        isSelected: viewModel.selection.contains(person.id),
                        isAsked: viewModel.isAsked(person)
                    ) {
                        viewModel.toggle(person)
                    }
                }
            } header: {
                if let activityLine {
                    Text("Also \(activityLine), closest first")
                }
            } footer: {
                Text("They'll get a notification and can reply with a note, and their location if they choose.")
            }
        }
        .safeAreaInset(edge: .bottom) { sendBar }
    }

    private var sendBar: some View {
        VStack(spacing: 8) {
            if let confirmation = viewModel.confirmation {
                Button {
                    onShowNotes()
                } label: {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)
            }
            Button {
                Task { await viewModel.sendRequests() }
            } label: {
                Group {
                    if viewModel.isSending {
                        ProgressView()
                            .tint(Color.onBrandAccent)
                    } else {
                        Text(viewModel.selection.isEmpty ? "Select people to ask" : "Ask for a note (\(viewModel.selection.count))")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.brand)
            .disabled(!viewModel.canSend)
        }
        .padding()
        .background(.bar)
    }

    private var activityLine: String? {
        viewModel.result?.activity.map { $0.name.prefix(1).lowercased() + $0.name.dropFirst() }
    }
}

private struct NearbyPersonRow: View {
    let person: Person
    let isSelected: Bool
    let isAsked: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isAsked ? "paperplane.circle.fill" : isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isAsked ? Color.secondary : isSelected ? Color.accentColor : Color.secondary)
                AvatarView(id: person.id, firstName: person.firstName, lastName: person.lastName, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.displayName)
                        .font(.headline)
                    if let note = person.status?.note {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if isAsked {
                        Text("Asked · waiting for a reply")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let meters = person.distanceMeters {
                    Text(DistanceText.approximate(meters))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAsked)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NearbyPeopleView(user: SampleData.user, services: .mock(), onShowNotes: {})
}

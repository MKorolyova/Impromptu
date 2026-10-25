//
//  NotesInboxView.swift
//  Impromptu-app
//

import MapKit
import SwiftUI

/// Note requests you've received (reply or decline) and sent (read the replies).
struct NotesInboxView: View {
    @State private var viewModel: NotesInboxViewModel
    @Environment(\.dismiss) private var dismiss

    init(user: User, services: Services, tab: NotesInboxViewModel.Tab = .received) {
        _viewModel = State(initialValue: NotesInboxViewModel(user: user, services: services, tab: tab))
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Notes", selection: $viewModel.tab) {
                    ForEach(NotesInboxViewModel.Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if viewModel.requests.isEmpty, viewModel.hasLoaded {
                    emptyState
                        .listRowBackground(Color.clear)
                }
                ForEach(viewModel.requests) { request in
                    NoteRequestRow(
                        request: request,
                        onReply: { viewModel.startReply(to: request) },
                        onDecline: { Task { await viewModel.decline(request) } }
                    )
                }
            }
            .overlay {
                if !viewModel.hasLoaded { ProgressView() }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
            .sheet(item: $viewModel.replyingTo) { request in
                NoteReplyView(request: request, viewModel: viewModel)
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { viewModel.errorMessage != nil && viewModel.replyingTo == nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var emptyState: some View {
        Group {
            switch viewModel.tab {
            case .received:
                ContentUnavailableView("No requests", systemImage: "tray",
                                       description: Text("When someone nearby asks where you are, it shows up here."))
            case .sent:
                ContentUnavailableView("Nothing sent", systemImage: "paperplane",
                                       description: Text("Ask people nearby for a note from the Nearby screen."))
            }
        }
    }
}

private struct NoteRequestRow: View {
    let request: NoteRequest
    let onReply: () -> Void
    let onDecline: () -> Void

    private var name: String { request.otherUser.displayName }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AvatarView(id: request.otherUser.id, firstName: request.otherUser.firstName,
                           lastName: request.otherUser.lastName, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.direction == .incoming ? "\(name) asked for a note" : "You asked \(name)")
                        .font(.headline)
                    HStack(spacing: 4) {
                        if let activity = request.activity {
                            Text(activity.name)
                            Text("·")
                        }
                        Text(request.createdAt, format: .relative(presentation: .named))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            switch (request.direction, request.status) {
            case (.incoming, .pending) where request.isOpen:
                HStack {
                    Button("Reply", systemImage: "arrowshape.turn.up.left.fill", action: onReply)
                        .buttonStyle(.borderedProminent)
                    Button("Decline", role: .destructive, action: onDecline)
                        .buttonStyle(.bordered)
                }
                .controlSize(.small)
            case (_, .pending):
                StatusTag(text: request.isOpen ? "Waiting for a reply…" : "Expired", systemImage: "clock")
            case (_, .declined):
                StatusTag(text: request.direction == .incoming ? "You declined" : "\(name) can't share right now",
                          systemImage: "hand.raised")
            case (_, .answered):
                if let reply = request.reply {
                    ReplyCard(reply: reply, author: request.direction == .incoming ? "You" : name)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct StatusTag: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

/// The reply text, place, and a map if a location was shared.
private struct ReplyCard: View {
    let reply: NoteRequest.Reply
    let author: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reply.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if let place = reply.placeLabel {
                Label(place, systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.medium))
            }
            if let location = reply.location {
                ReplyMap(location: location, title: reply.placeLabel ?? author)
            }
            Text("\(author) · \(reply.respondedAt, format: .relative(presentation: .named))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ReplyMap: View {
    let location: NoteRequest.ReplyLocation
    let title: String

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }

    private var mapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(location.latitude),\(location.longitude)"),
            URLQueryItem(name: "q", value: title),
        ]
        return components?.url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 400, longitudinalMeters: 400))) {
                Marker(title, coordinate: coordinate)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .allowsHitTesting(false)

            if let mapsURL {
                Link(destination: mapsURL) {
                    Label("Open in Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }
}

/// Answer a request: a note, optionally where you are.
private struct NoteReplyView: View {
    let request: NoteRequest
    @Bindable var viewModel: NotesInboxViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Note", text: $viewModel.draft.text, prompt: Text("e.g. Come say hi, I'm by the windows"), axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Reply to \(request.otherUser.displayName)")
                } footer: {
                    Text("\(viewModel.draft.text.count)/\(NoteReplyDraft.maxTextLength)")
                }

                Section {
                    TextField("Place (optional)", text: $viewModel.draft.placeLabel, prompt: Text("e.g. PCL, 3rd floor"))
                    Toggle(isOn: $viewModel.draft.includeLocation) {
                        Label("Share my location", systemImage: "location.fill")
                    }
                } footer: {
                    Text(viewModel.draft.includeLocation
                         ? "\(request.otherUser.displayName) will see a pin where you are now."
                         : "Only your note and place are sent.")
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Send a Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSendingReply {
                        ProgressView()
                    } else {
                        Button("Send") {
                            Task {
                                if await viewModel.sendReply() { dismiss() }
                            }
                        }
                        .disabled(!viewModel.draft.isValid)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Received") {
    NotesInboxView(user: SampleData.user, services: .mock())
}

#Preview("Sent") {
    NotesInboxView(user: SampleData.user, services: .mock(), tab: .sent)
}

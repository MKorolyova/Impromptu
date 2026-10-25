//
//  AddFriendNearbyView.swift
//  Impromptu-app
//

import SwiftUI
import UIKit

/// Add Friend → Nearby, as a sheet: hold the tops of two phones together, then both accept.
struct AddFriendNearbyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AddFriendNearbyViewModel

    init(user: User, services: Services) {
        _viewModel = State(initialValue: AddFriendNearbyViewModel(user: user, services: services))
    }

    var body: some View {
        VStack(spacing: 24) {
            SheetHeader(title: "Add a friend nearby", subtitle: subtitle)
            Spacer(minLength: 0)
            phaseContent
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            Spacer(minLength: 0)
            if viewModel.phase == .looking {
                NearbyPeopleList(viewModel: viewModel)
            }
        }
        .padding(24)
        .animation(.snappy, value: viewModel.phase)
        .animation(.snappy, value: viewModel.peers)
        .presentationDetents([.large])
        .brandSheet()
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .sensoryFeedback(.impact(weight: .medium), trigger: offeredPeerId)
        .sensoryFeedback(.success, trigger: isFriends)
        // "Said not now" and the like go away on their own.
        .task(id: viewModel.phase) {
            guard case .ended = viewModel.phase else { return }
            try? await Task.sleep(for: .seconds(2.5))
            viewModel.lookAgain()
        }
    }

    private var subtitle: String {
        viewModel.usesTouch
            ? "Ask your friend to open this screen too, then hold the tops of your phones together."
            : "Ask your friend to open this screen too, then pick them below."
    }

    private var offeredPeerId: String? {
        if case .offer(let peer) = viewModel.phase { peer.id } else { nil }
    }

    private var isFriends: Bool {
        if case .friends = viewModel.phase { true } else { false }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch viewModel.phase {
        case .looking:
            VStack(spacing: 20) {
                PulsingPhones()
                Text(viewModel.usesTouch ? "Hold the tops of your phones together" : "Looking for your friend…")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
                if !viewModel.canMeasureDistance {
                    Hint(text: "This iPhone can't sense how close another phone is, so pick your friend from the list.")
                } else if !viewModel.isDistanceAllowed {
                    Hint(text: "Turn on Nearby Interactions for \(Brand.appName) in Settings to add friends by touching phones.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(.brand(.secondary, compact: true))
                }
            }

        case .offer(let peer):
            PeerPrompt(peer: peer, title: "Become friends with \(peer.identity.displayName)?",
                       detail: "You'll each see the other's location and notes. You can change that in Settings.") {
                HStack(spacing: 12) {
                    Button("Not now", action: viewModel.decline)
                        .buttonStyle(.brand(.secondary))
                    Button("Accept") { Task { await viewModel.accept() } }
                        .buttonStyle(.brand)
                }
            }

        case .waiting(let peer):
            PeerPrompt(peer: peer, title: "Waiting for \(peer.identity.displayName)…",
                       detail: "They need to tap Accept on their phone.") {
                VStack(spacing: 16) {
                    ProgressView()
                    Button("Cancel", action: viewModel.decline)
                        .buttonStyle(.brand(.secondary, compact: true))
                }
            }

        case .adding(let peer):
            PeerPrompt(peer: peer, title: "Adding \(peer.identity.displayName)…", detail: nil) {
                ProgressView()
            }

        case .friends(let friend):
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.brandAccent)
                    .accessibilityHidden(true)
                Text("You and \(friend.nickname ?? friend.firstName) are friends")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("They'll show up first in your feed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Done") { dismiss() }
                    .buttonStyle(.brand)
                Button("Add someone else", action: viewModel.lookAgain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandAccent)
            }

        case .ended(let message):
            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

        case .failed(let peer, let message):
            PeerPrompt(peer: peer, title: "Couldn't add \(peer.identity.displayName)", detail: nil) {
                VStack(spacing: 12) {
                    InlineError(message: message)
                    HStack(spacing: 12) {
                        Button("Not now", action: viewModel.lookAgain)
                            .buttonStyle(.brand(.secondary))
                        Button("Try Again") { Task { await viewModel.retry() } }
                            .buttonStyle(.brand)
                    }
                }
            }
        }
    }
}

/// Who's nearby with the screen open: distances while touch works, an Add button when it doesn't.
private struct NearbyPeopleList: View {
    let viewModel: AddFriendNearbyViewModel
    @State private var showsHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nearby")
                .font(.headline)
            if viewModel.peers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Looking for phones with Add Friend open…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if showsHelp {
                        Text("Both phones need Bluetooth and Wi-Fi on, and \(Brand.appName) allowed to find local devices.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .insetBackground()
                .task {
                    try? await Task.sleep(for: .seconds(12))
                    withAnimation { showsHelp = true }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.peers) { peer in
                        row(peer)
                        if peer.id != viewModel.peers.last?.id {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .insetBackground()
            }
        }
    }

    private func row(_ peer: NearbyPeer) -> some View {
        HStack(spacing: 12) {
            AvatarView(id: peer.identity.userId, firstName: peer.identity.firstName, lastName: peer.identity.lastName,
                       size: 36)
            Text(peer.identity.displayName)
                .font(.body.weight(.medium))
            Spacer()
            // Touching works only when both phones measure; otherwise ask from here.
            if viewModel.usesTouch, let distance = peer.distance {
                Text(Self.distanceText(distance))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Button("Add") { Task { await viewModel.request(peer) } }
                    .buttonStyle(.brand(.primary, compact: true))
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    static func distanceText(_ meters: Float) -> String {
        meters < 1 ? "\(Int((meters * 100).rounded())) cm" : String(format: "%.1f m", meters)
    }
}

/// The other person, big, with a question and its buttons.
private struct PeerPrompt<Actions: View>: View {
    let peer: NearbyPeer
    let title: String
    let detail: String?
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 16) {
            AvatarView(id: peer.identity.userId, firstName: peer.identity.firstName, lastName: peer.identity.lastName,
                       size: 88, usesBrandColors: true)
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            actions()
                .padding(.top, 4)
        }
    }
}

/// Two brand circles breathing around a phone, while it looks for others.
private struct PulsingPhones: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Brand.indigo.opacity(0.18))
                .frame(width: 168, height: 168)
                .scaleEffect(isPulsing ? 1.08 : 0.86)
            Circle()
                .fill(Brand.sky.opacity(0.55))
                .frame(width: 118, height: 118)
                .scaleEffect(isPulsing ? 0.94 : 1.04)
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Brand.indigo)
        }
        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear { isPulsing = true }
        .accessibilityHidden(true)
    }
}

private struct Hint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    Color.appBackground
        .sheet(isPresented: .constant(true)) {
            AddFriendNearbyView(user: SampleData.user, services: .mock())
        }
}

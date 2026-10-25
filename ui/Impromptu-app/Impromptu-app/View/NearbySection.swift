//
//  NearbySection.swift
//  Impromptu-app
//

import SwiftUI
import UIKit

/// "Nearby, doing the same": the opt-in switch and the people within about a mile who match your activity.
struct NearbySection: View {
    let viewModel: HomeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toggleCard
            if viewModel.isNearbyEnabled, let nearby = viewModel.nearby, nearby.activity != nil {
                ForEach(nearby.users) { person in
                    if let status = person.status {
                        PersonCard(person: person, status: status)
                    }
                }
            }
        }
    }

    private var toggleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { viewModel.isNearbyEnabled },
                set: { enabled in Task { await viewModel.setNearbyAlerts(enabled) } }
            )) {
                Label("Nearby alerts", systemImage: "location.circle.fill")
                    .font(.headline)
            }
            .disabled(viewModel.isChangingNearby)

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let notice = viewModel.nearbyNotice {
                NoticeView(notice: notice)
            }
        }
        .padding()
        .cardBackground()
    }

    private var summary: String {
        guard viewModel.isNearbyEnabled else {
            return "Get a notification, at most once an hour, when someone new within a mile is doing what you're doing."
        }
        guard let nearby = viewModel.nearby else { return "Looking for people nearby…" }
        guard let activity = nearby.activity else { return "Set a status to find people nearby doing the same." }
        let name = activity.name.prefix(1).lowercased() + activity.name.dropFirst()
        switch nearby.users.count {
        case 0: return "No one within a mile is \(name) right now. We'll let you know."
        case 1: return "1 person within a mile is also \(name)."
        default: return "\(nearby.users.count) people within a mile are also \(name)."
        }
    }
}

private struct NoticeView: View {
    let notice: NearbyNotice

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.caption)
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: settingsURL)
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var message: String {
        switch notice {
        case .locationDenied:
            "Location access is off, so Impromptu can't find people nearby."
        case .whileUsingOnly:
            "Location is set to While Using. Choose Always so Impromptu can check while it's closed."
        case .notificationsDenied:
            "Notifications are off. You'll only see nearby people here in the app."
        }
    }
}

#Preview {
    @Previewable @State var viewModel = HomeViewModel(user: SampleData.user, services: .mock())
    ScrollView {
        NearbySection(viewModel: viewModel)
            .padding()
    }
    .background(Color.feedBackground)
    .task { await viewModel.load() }
}

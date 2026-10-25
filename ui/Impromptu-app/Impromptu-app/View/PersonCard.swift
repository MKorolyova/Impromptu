//
//  PersonCard.swift
//  Impromptu-app
//

import SwiftUI
import UIKit

/// A feed post: someone and what they're up to right now.
struct PersonCard: View {
    let person: Person
    let status: Status

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(id: person.id, firstName: person.firstName, lastName: person.lastName, isActive: true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(person.displayName)
                        .font(.headline)
                    Spacer()
                    if let meters = person.distanceMeters {
                        Text(DistanceText.approximate(meters))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tint)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(status.startedAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                StatusLine(status: status)

                if let note = status.note {
                    Text(note)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("until \(status.expiresAt, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .cardBackground()
        .accessibilityElement(children: .combine)
    }
}

/// A compact row for someone without a live status.
struct IdlePersonRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(id: person.id, firstName: person.firstName, lastName: person.lastName, size: 36)
                .opacity(0.6)
            Text(person.displayName)
                .font(.subheadline)
            Spacer()
            Text("No status")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Activity icon and name, shared by feed cards and your own status.
struct StatusLine: View {
    let status: Status

    var body: some View {
        HStack(spacing: 8) {
            ActivityIcon(activityName: status.activity.name, size: 26)
            Text(status.activity.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
        }
    }
}

extension Color {
    static let feedBackground = Color(uiColor: .systemGroupedBackground)
    static let cardFill = Color(uiColor: .secondarySystemGroupedBackground)
}

extension View {
    /// The rounded card used across the home feed.
    func cardBackground() -> some View {
        background(Color.cardFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(SampleData.people) { person in
                if let status = person.activeStatus {
                    PersonCard(person: person, status: status)
                } else {
                    IdlePersonRow(person: person)
                }
            }
        }
        .padding()
    }
    .background(Color.feedBackground)
}

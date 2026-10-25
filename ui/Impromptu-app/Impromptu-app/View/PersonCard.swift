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

/// A compact row in a list of people: their activity if they have one, "No status" otherwise.
struct PersonRow: View {
    let person: Person

    var body: some View {
        let status = person.activeStatus
        HStack(spacing: 12) {
            AvatarView(id: person.id, firstName: person.firstName, lastName: person.lastName, size: 36,
                       isActive: status != nil)
                .opacity(status == nil ? 0.6 : 1)
            Text(person.displayName)
                .font(.subheadline.weight(status == nil ? .regular : .semibold))
            Spacer()
            if let status {
                HStack(spacing: 6) {
                    ActivityIcon(activityName: status.activity.name, size: 22)
                    Text(status.activity.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            } else {
                Text("No status")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
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

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(SampleData.people) { person in
                if let status = person.activeStatus {
                    PersonCard(person: person, status: status)
                } else {
                    PersonRow(person: person)
                }
            }
        }
        .padding()
    }
    .background(Color.appBackground)
}

//
//  StatusWidget.swift
//  ImpromptuWidget
//

import SwiftUI
import WidgetKit

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Reads the snapshot the app writes to the App Group container. The widget
/// never talks to the API itself; the app reloads timelines when data changes.
struct StatusProvider: TimelineProvider {
    private let store = SharedStore.standard

    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        let snapshot = context.isPreview ? .placeholder : (store.load(.widgetSnapshot) ?? .empty)
        completion(StatusEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let now = Date.now
        let snapshot = store.load(.widgetSnapshot) ?? .empty
        var entries = [StatusEntry(date: now, snapshot: snapshot)]
        // Re-render when the next status expires so stale statuses disappear.
        if let expiry = snapshot.nextExpiry(after: now) {
            entries.append(StatusEntry(date: expiry, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StatusWidget", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Friends' Status")
        .description("See what you and your friends are up to.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    private var myStatus: StatusSnapshot? {
        entry.snapshot.myStatus.flatMap { $0.isActive(at: entry.date) ? $0 : nil }
    }

    private var friends: [FriendStatusSnapshot] {
        Array(entry.snapshot.activeFriends(at: entry.date).prefix(family == .systemSmall ? 2 : 4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(myStatus?.activityName ?? "No status")
                .font(.headline)
                .lineLimit(1)

            Divider()

            if friends.isEmpty {
                Text("No friends active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(friends) { friend in
                HStack {
                    Text(friend.displayName).bold()
                    Text(friend.status?.activityName ?? "")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview(as: .systemMedium) {
    StatusWidget()
} timeline: {
    StatusEntry(date: .now, snapshot: .placeholder)
    StatusEntry(date: .now, snapshot: .empty)
}

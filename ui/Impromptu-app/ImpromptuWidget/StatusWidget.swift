//
//  StatusWidget.swift
//  ImpromptuWidget
//

import SwiftUI
import WidgetKit

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// The app's light/dark choice, so the widget matches it.
    var theme: AppTheme = .system
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
        completion(StatusEntry(date: .now, snapshot: snapshot, theme: .current))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let now = Date.now
        let snapshot = store.load(.widgetSnapshot) ?? .empty
        let theme = AppTheme.current
        var entries = [StatusEntry(date: now, snapshot: snapshot, theme: theme)]
        // Re-render when the next status expires so stale statuses disappear.
        if let expiry = snapshot.nextExpiry(after: now) {
            entries.append(StatusEntry(date: expiry, snapshot: snapshot, theme: theme))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StatusWidget", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Your Status")
        .description("What you're up to, and on the large size, your friends too.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }

    private var myStatus: StatusSnapshot? {
        snapshot.myStatus.flatMap { $0.isActive(at: entry.date) ? $0 : nil }
    }

    private var isSignedIn: Bool { snapshot.userName != nil }

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.surface }
            .colorScheme(for: entry.theme)
    }

    @ViewBuilder
    private var content: some View {
        if !isSignedIn {
            StatusCard(title: Brand.appName, detail: Text("Sign in to share what you're up to."), symbol: "sparkles")
        } else {
            switch family {
            case .systemSmall: small
            case .systemLarge: large
            default: StatusCard(status: myStatus, timezone: snapshot.timezone, badgeSize: 76)
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusBadge(symbol: myStatus.map { ActivitySymbol.name(for: $0.activityName) } ?? "sparkles", size: 54)
            Spacer(minLength: 0)
            Text(myStatus?.activityName ?? "No status yet")
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Group {
                if let myStatus {
                    Text("Until \(myStatus.expiresAt, style: .time)")
                } else {
                    Text("Tap to share")
                }
            }
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surfaceInset, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var large: some View {
        let friends = Array(snapshot.activeFriends(at: entry.date).prefix(3))
        return VStack(alignment: .leading, spacing: 10) {
            StatusCard(status: myStatus, timezone: snapshot.timezone, badgeSize: 72)
                .frame(height: 112)

            Text("Friends")
                .font(.system(.subheadline, design: .rounded, weight: .heavy))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            if friends.isEmpty {
                Text("No friends have a status right now.")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(friends) { friend in
                if let status = friend.status {
                    FriendStatusRow(name: friend.displayName, status: status)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// A friend's status as a smaller version of the main tile.
private struct FriendStatusRow: View {
    let name: String
    let status: StatusSnapshot

    var body: some View {
        HStack(spacing: 12) {
            StatusBadge(symbol: ActivitySymbol.name(for: status.activityName), size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name) | \(status.activityName)")
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                    .lineLimit(1)
                Group {
                    if let note = status.note {
                        Text(note)
                    } else {
                        Text("Until \(status.expiresAt, style: .time)")
                    }
                }
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.surfaceInset, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension View {
    /// Applies the app's light/dark choice; `.system` leaves the home screen's appearance.
    @ViewBuilder
    func colorScheme(for theme: AppTheme) -> some View {
        if let scheme = theme.colorScheme {
            environment(\.colorScheme, scheme)
        } else {
            self
        }
    }
}

#Preview("Light", as: .systemMedium) {
    StatusWidget()
} timeline: {
    StatusEntry(date: .now, snapshot: .placeholder, theme: .light)
    StatusEntry(date: .now, snapshot: .empty, theme: .light)
}

#Preview("Dark", as: .systemMedium) {
    StatusWidget()
} timeline: {
    StatusEntry(date: .now, snapshot: .placeholder, theme: .dark)
}

#Preview("Large", as: .systemLarge) {
    StatusWidget()
} timeline: {
    StatusEntry(date: .now, snapshot: .placeholder)
}

#Preview("Small", as: .systemSmall) {
    StatusWidget()
} timeline: {
    StatusEntry(date: .now, snapshot: .placeholder)
}

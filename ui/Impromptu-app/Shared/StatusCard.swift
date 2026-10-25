//
//  StatusCard.swift
//  Impromptu-app
//
//  Compiled into both the app and the widget extension: the home screen shows your status in the
//  same tile as the widget.
//

import SwiftUI

/// The activity's symbol on the brand's two-tone disc.
struct StatusBadge: View {
    let symbol: String
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle()
                .fill(Brand.indigo)
            Circle()
                .fill(Brand.sky)
                .frame(width: size * 0.86, height: size * 0.86)
                .offset(x: size * 0.05, y: size * 0.06)
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.black)
                .offset(x: size * 0.05, y: size * 0.06)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Text on one inset tile, the badge on another: "Running | GMT-5" over the note.
struct StatusCard: View {
    let title: String
    let detail: Text?
    let symbol: String
    var badgeSize: CGFloat = 64

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail {
                    detail
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .lineLimit(2)
                }
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.surfaceInset, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            StatusBadge(symbol: symbol, size: badgeSize)
                .padding(12)
                .frame(maxHeight: .infinity)
                .background(Color.surfaceInset, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }
}

extension StatusCard {
    /// Your status with your time zone, and the note or when it ends. An invitation when there's none.
    init(status: StatusSnapshot?, timezone: String?, badgeSize: CGFloat = 64) {
        if let status {
            title = [status.activityName, GMTOffset.label(for: timezone)].compactMap { $0 }.joined(separator: " | ")
            detail = status.note.map { Text($0) } ?? Text("Until \(status.expiresAt, style: .time)")
            symbol = ActivitySymbol.name(for: status.activityName)
        } else {
            title = "No status yet"
            detail = Text("What are you up to?")
            symbol = "sparkles"
        }
        self.badgeSize = badgeSize
    }
}

nonisolated enum GMTOffset {
    /// "GMT-5", "GMT+5:30" or "GMT" for the zone at `date`; nil for an unknown zone.
    static func label(for identifier: String?, at date: Date = .now) -> String? {
        guard let identifier, let zone = TimeZone(identifier: identifier) else { return nil }
        let seconds = zone.secondsFromGMT(for: date)
        guard seconds != 0 else { return "GMT" }
        let hours = abs(seconds) / 3600
        let minutes = abs(seconds) % 3600 / 60
        let sign = seconds < 0 ? "-" : "+"
        return minutes == 0 ? "GMT\(sign)\(hours)" : "GMT\(sign)\(hours):\(String(format: "%02d", minutes))"
    }
}

#Preview {
    VStack(spacing: 16) {
        StatusCard(status: WidgetSnapshot.placeholder.myStatus, timezone: "America/Chicago")
            .frame(height: 120)
        StatusCard(status: nil, timezone: nil)
            .frame(height: 120)
    }
    .padding()
    .background(Color.surface)
}

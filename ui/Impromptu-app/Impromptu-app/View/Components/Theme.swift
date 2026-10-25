//
//  Theme.swift
//  Impromptu-app
//
//  Building blocks that give every screen the widget's look. Colors live in Shared/Brand.swift.
//

import SwiftUI

/// Capsule buttons in the brand colors. Primary is filled; secondary is tinted.
struct BrandButtonStyle: ButtonStyle {
    enum Prominence {
        case primary
        case secondary
    }

    var prominence: Prominence = .primary
    /// Fits its label instead of filling the width, e.g. in a toolbar.
    var isCompact = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(isCompact ? .subheadline : .headline, design: .rounded, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(prominence == .primary ? Color.onBrandAccent : Color.brandAccent)
            .padding(.horizontal, isCompact ? 16 : 24)
            .frame(maxWidth: isCompact ? nil : .infinity, minHeight: isCompact ? 38 : 54)
            .background(prominence == .primary ? Color.brandAccent : Color.brandAccent.opacity(0.14), in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BrandButtonStyle {
    static var brand: BrandButtonStyle { BrandButtonStyle() }

    static func brand(_ prominence: BrandButtonStyle.Prominence, compact: Bool = false) -> BrandButtonStyle {
        BrandButtonStyle(prominence: prominence, isCompact: compact)
    }
}

extension View {
    /// The rounded card used across the app: the widget's outer panel.
    func cardBackground(cornerRadius: CGFloat = 24) -> some View {
        background(Color.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.surfaceStroke)
            }
    }

    /// A tile inside a card or sheet: the widget's inner panels.
    func insetBackground(cornerRadius: CGFloat = 16) -> some View {
        background(Color.surfaceInset, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Text fields sit on inset tiles.
    func brandField() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 15)
            .insetBackground()
    }

    /// Bottom sheets share the card surface, rounded corners and grabber.
    func brandSheet() -> some View {
        presentationBackground(Color.surface)
            .presentationCornerRadius(32)
            .presentationDragIndicator(.visible)
    }
}

/// Title and explanation at the top of a sheet or step.
struct SheetHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.title, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A form error shown in place, next to what caused it.
struct InlineError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The app background with soft glows in the two brand colors.
struct BrandBackdrop: View {
    var body: some View {
        ZStack {
            Color.appBackground
            Circle()
                .fill(Brand.sky.opacity(0.5))
                .frame(width: 420, height: 420)
                .blur(radius: 100)
                .offset(x: -150, y: -280)
            Circle()
                .fill(Brand.indigo.opacity(0.3))
                .frame(width: 380, height: 380)
                .blur(radius: 120)
                .offset(x: 170, y: 300)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Lays out children left to right, wrapping onto new lines, like tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !current.indices.isEmpty, current.width + spacing + size.width > width {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width += (current.indices.isEmpty ? 0 : spacing) + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// A picked activity. Locked ones are always included; the rest can be removed.
struct ActivityTag: View {
    let name: String
    var isLocked = false
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ActivitySymbol.name(for: name))
                .font(.caption.weight(.bold))
            Text(name)
                .font(.subheadline.weight(.semibold))
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .accessibilityLabel("Always included")
            } else if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Remove \(name)")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, isLocked ? 12 : 8)
        .padding(.vertical, 8)
        .foregroundStyle(isLocked ? Color.primary : Color.onBrandAccent)
        .background(isLocked ? Color.surfaceInset : Color.brandAccent, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

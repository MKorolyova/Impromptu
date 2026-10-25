//
//  AvatarView.swift
//  Impromptu-app
//

import SwiftUI

/// Initials on a color that's stable per user.
struct AvatarView: View {
    let id: UUID
    let firstName: String
    let lastName: String
    var size: CGFloat = 44
    /// Draws a ring when the person has a live status.
    var isActive = false

    private static let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .green, .indigo, .red]

    private var color: Color {
        Self.palette[Int(id.uuid.0) % Self.palette.count]
    }

    private var initials: String {
        [firstName, lastName].compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: Circle())
            .overlay {
                if isActive {
                    Circle()
                        .strokeBorder(.green, lineWidth: 2.5)
                        .padding(-4)
                }
            }
            .padding(isActive ? 4 : 0)
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 16) {
        AvatarView(id: UUID(), firstName: "Sam", lastName: "Lee", isActive: true)
        AvatarView(id: UUID(), firstName: "Jordan", lastName: "Park", size: 56)
        AvatarView(id: UUID(), firstName: "Priya", lastName: "Shah", size: 32)
    }
}

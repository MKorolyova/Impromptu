//
//  ActivityIcon.swift
//  Impromptu-app
//

import SwiftUI

/// The activity's symbol in a tinted rounded square.
struct ActivityIcon: View {
    let activityName: String
    var size: CGFloat = 28
    var tint: Color = .accentColor

    var body: some View {
        Image(systemName: ActivitySymbol.name(for: activityName))
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

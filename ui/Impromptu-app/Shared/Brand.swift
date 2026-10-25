//
//  Brand.swift
//  Impromptu-app
//
//  Compiled into both the app and the widget extension, so both look the same.
//

import SwiftUI
import UIKit

nonisolated enum Brand {
    static let appName = "Impromptu"
    /// #9CCAFF
    static let sky = Color(uiColor: UIColor(hex: 0x9CCAFF))
    /// #1800AD
    static let indigo = Color(uiColor: UIColor(hex: 0x1800AD))
}

// MARK: - Theme colors
// Each token has a light and a dark value. Cards and their inset tiles mirror the widget's outer
// panel and inner tiles.

nonisolated extension Color {
    /// Buttons, links and selection: indigo on light, sky on dark, so both read clearly.
    static let brandAccent = Color(light: UIColor(hex: 0x1800AD), dark: UIColor(hex: 0x9CCAFF))
    /// Text and icons drawn on `brandAccent`.
    static let onBrandAccent = Color(light: .white, dark: UIColor(hex: 0x1800AD))
    /// Behind everything.
    static let appBackground = Color(light: UIColor(hex: 0xF2F4FA), dark: UIColor(hex: 0x05060B))
    /// Cards and sheets: the widget's outer panel.
    static let surface = Color(light: .white, dark: UIColor(hex: 0x16171E))
    /// Fields and tiles inside a surface: the widget's inner panels.
    static let surfaceInset = Color(light: UIColor(hex: 0xEDF1FA), dark: UIColor(hex: 0x0B0C11))
    /// Hairline around cards.
    static let surfaceStroke = Color(light: UIColor(hex: 0x1800AD, alpha: 0.08), dark: UIColor(white: 1, alpha: 0.08))

    /// Resolves for light or dark appearance, in the app and in widgets.
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

nonisolated extension UIColor {
    /// sRGB from `0xRRGGBB`.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Appearance

/// Light, dark, or follow the system. Kept in App Group defaults so the widget matches the app.
nonisolated enum AppTheme: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    static let storageKey = "appTheme"
    /// One instance, so every `@AppStorage` reading the theme sees changes immediately.
    static let store = UserDefaults(suiteName: AppGroup.identifier) ?? .standard

    static var current: AppTheme {
        store.string(forKey: storageKey).flatMap(AppTheme.init(rawValue:)) ?? .system
    }

    /// Nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

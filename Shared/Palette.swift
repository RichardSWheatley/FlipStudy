import SwiftUI

// Shared by the app and the widget, so the widget wears the same colours.

// MARK: - Deck colours

/// The bright colours a deck can wear. Kids pick one when they make a deck;
/// decks made before there was a choice get one picked for them, the same on
/// every device.
enum DeckPalette: Int, CaseIterable, Identifiable {
    case ocean, grape, berry, tangerine, sunshine, lime, mint, bubblegum

    var id: Int { rawValue }

    var top: Color {
        switch self {
        case .ocean: Color(red: 0.30, green: 0.67, blue: 0.97)
        case .grape: Color(red: 0.69, green: 0.59, blue: 0.99)
        case .berry: Color(red: 1.00, green: 0.42, blue: 0.48)
        case .tangerine: Color(red: 1.00, green: 0.66, blue: 0.30)
        case .sunshine: Color(red: 1.00, green: 0.80, blue: 0.20)
        case .lime: Color(red: 0.55, green: 0.83, blue: 0.27)
        case .mint: Color(red: 0.22, green: 0.85, blue: 0.66)
        case .bubblegum: Color(red: 0.97, green: 0.51, blue: 0.67)
        }
    }

    var bottom: Color {
        switch self {
        case .ocean: Color(red: 0.11, green: 0.44, blue: 0.86)
        case .grape: Color(red: 0.44, green: 0.28, blue: 0.91)
        case .berry: Color(red: 0.90, green: 0.18, blue: 0.36)
        case .tangerine: Color(red: 0.98, green: 0.42, blue: 0.13)
        case .sunshine: Color(red: 0.96, green: 0.58, blue: 0.00)
        case .lime: Color(red: 0.22, green: 0.62, blue: 0.24)
        case .mint: Color(red: 0.03, green: 0.60, blue: 0.47)
        case .bubblegum: Color(red: 0.84, green: 0.20, blue: 0.42)
        }
    }

    /// The colour for text and icons drawn *on white* in this deck's colour.
    var ink: Color { bottom }

    var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var name: String {
        switch self {
        case .ocean: "Ocean"
        case .grape: "Grape"
        case .berry: "Berry"
        case .tangerine: "Tangerine"
        case .sunshine: "Sunshine"
        case .lime: "Lime"
        case .mint: "Mint"
        case .bubblegum: "Bubblegum"
        }
    }

    /// A colour for a deck that never chose one. Seeded from the deck's id so
    /// it's the same on every device and never changes on its own.
    static func automatic(for seed: String) -> DeckPalette {
        allCases[stableHash(seed) % allCases.count]
    }
}

/// A hash that is the same on every launch and every device (Swift's own
/// `hashValue` is reseeded each run, so it can't pick a colour that sticks).
func stableHash(_ text: String) -> Int {
    text.unicodeScalars.reduce(5381) { ($0 &* 33 &+ Int($1.value)) & 0x7fffffff }
}


// MARK: - The app's own colour

/// The colour kids pick for FlipStudy itself. It tints the app, recolours the
/// widget, and swaps the home-screen icon to match. Kept in the App Group so
/// the widget can read it.
enum AppTheme: String, CaseIterable, Identifiable {
    case classic, ocean, grape, berry, tangerine, sunshine, lime, mint, bubblegum

    var id: String { rawValue }

    static let storageKey = "appTheme"
    static var defaults: UserDefaults { UserDefaults(suiteName: WidgetSnapshot.appGroup) ?? .standard }
    static var current: AppTheme { AppTheme(rawValue: defaults.string(forKey: storageKey) ?? "") ?? .classic }

    /// The deck colour this theme is named after; nil for Classic.
    private var palette: DeckPalette? {
        switch self {
        case .classic: nil
        case .ocean: .ocean
        case .grape: .grape
        case .berry: .berry
        case .tangerine: .tangerine
        case .sunshine: .sunshine
        case .lime: .lime
        case .mint: .mint
        case .bubblegum: .bubblegum
        }
    }

    /// The icon's two tones, in Display P3. Must match scripts/make-app-icons.swift,
    /// so the app, its widget and its Home Screen icon are the same colours.
    private var tones: (top: (Double, Double, Double), bottom: (Double, Double, Double)) {
        switch self {
        case .classic: ((0.33, 0.50, 1.00), (0.48, 0.22, 0.94))
        case .ocean: ((0.20, 0.80, 1.00), (0.10, 0.38, 0.95))
        case .grape: ((0.80, 0.56, 1.00), (0.45, 0.20, 0.92))
        case .berry: ((1.00, 0.46, 0.44), (0.88, 0.10, 0.42))
        case .tangerine: ((1.00, 0.76, 0.24), (1.00, 0.36, 0.12))
        case .sunshine: ((1.00, 0.88, 0.28), (1.00, 0.58, 0.04))
        case .lime: ((0.72, 0.92, 0.24), (0.18, 0.64, 0.26))
        case .mint: ((0.36, 0.95, 0.80), (0.00, 0.58, 0.54))
        case .bubblegum: ((1.00, 0.62, 0.80), (0.90, 0.18, 0.60))
        }
    }

    var top: Color { Color(.displayP3, red: tones.top.0, green: tones.top.1, blue: tones.top.2) }
    var bottom: Color { Color(.displayP3, red: tones.bottom.0, green: tones.bottom.1, blue: tones.bottom.2) }

    /// Light at the top, deep at the bottom, like the icon.
    var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    /// Warm themes get white sparkles on the icon; yellow ones would vanish.
    var sparkleColor: Color {
        switch self {
        case .tangerine, .sunshine, .lime: .white
        default: Color(.displayP3, red: 1, green: 0.86, blue: 0.30)
        }
    }

    var name: String { palette?.name ?? "Classic" }

    /// The Home Screen icon for this colour with `picture` on the front card;
    /// nil is the primary icon (Classic with the A+). Names match the .icon
    /// files scripts/make-app-icons.swift writes.
    func iconName(with picture: AppIconPicture = .aPlus) -> String? {
        switch picture {
        case .aPlus: palette.map { "AppIcon-\($0.name)" }
        case .hundred: "AppIcon-\(name)-100"
        }
    }
}

/// The grade on the icon's front card, picked alongside the colour.
enum AppIconPicture: String, CaseIterable, Identifiable {
    case aPlus, hundred

    var id: String { rawValue }

    static let storageKey = "appIconPicture"

    var name: String {
        switch self {
        case .aPlus: "A+"
        case .hundred: "100"
        }
    }
}

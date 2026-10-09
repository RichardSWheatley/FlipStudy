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

    /// The deck colour this theme borrows; classic is the original icon's indigo.
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

    var top: Color { palette?.top ?? Color(red: 0.38, green: 0.47, blue: 0.98) }
    var bottom: Color { palette?.bottom ?? Color(red: 0.21, green: 0.27, blue: 0.85) }

    var gradient: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var name: String { palette?.name ?? "Classic" }

    /// The alternate app icon for this theme; nil is the primary icon.
    var iconName: String? { palette.map { "AppIcon-\($0.name)" } }
}

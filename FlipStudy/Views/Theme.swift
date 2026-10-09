import SwiftUI
import WidgetKit

// MARK: - Deck emoji

enum DeckEmoji {
    /// What the picker offers.
    static let choices = ["📚", "🧠", "🚀", "🦖", "🌟", "🎨", "🔬", "🌍", "🎵", "🐙",
                          "⚽️", "🦄", "🍕", "🐶", "🌈", "🧪", "✏️", "🔢", "🗣️", "🏰"]

    /// A starting emoji for a deck that never chose one: a guess from its
    /// title or subject when there's an obvious match, otherwise one seeded
    /// from the deck's id.
    static func automatic(title: String, subject: String, seed: String) -> String {
        let text = "\(title) \(subject)".lowercased()
        let guesses: [(keys: [String], emoji: String)] = [
            (["spanish", "español", "french", "italian", "german", "japanese", "chinese", "language", "vocab", "words"], "🗣️"),
            (["math", "maths", "times", "multiplication", "fraction", "algebra", "number"], "🔢"),
            (["science", "chemistry", "chemical", "physics", "biology", "atom"], "🔬"),
            (["space", "planet", "solar", "moon", "star"], "🚀"),
            (["dinosaur", "fossil"], "🦖"),
            (["history", "war", "president", "king", "queen"], "🏰"),
            (["geography", "country", "capital", "map", "state"], "🌍"),
            (["music", "piano", "song", "note"], "🎵"),
            (["art", "color", "colour", "paint"], "🎨"),
            (["animal", "dog", "cat", "pet"], "🐶"),
            (["spelling", "reading", "english", "grammar"], "✏️"),
        ]
        // Whole words only, so "Education" doesn't count as "cat". Longer keys
        // also match their plurals and endings ("planets", "dinosaurs").
        let words = text.split(whereSeparator: { !$0.isLetter }).map(String.init)
        let matches: (String) -> Bool = { key in
            words.contains { $0 == key || (key.count >= 5 && $0.hasPrefix(key)) }
        }
        if let match = guesses.first(where: { $0.keys.contains(where: matches) }) {
            return match.emoji
        }
        return choices[stableHash(seed) % choices.count]
    }
}

extension Deck {
    var palette: DeckPalette {
        DeckPalette(rawValue: colorIndex) ?? .automatic(for: id.uuidString)
    }

    var displayEmoji: String {
        emoji.isEmpty ? DeckEmoji.automatic(title: title, subject: subject, seed: id.uuidString) : emoji
    }
}

// MARK: - Cheering

enum Cheer {
    static let correct = ["Nice!", "You got it!", "Boom!", "Awesome!", "Yes!", "Super!", "Nailed it!", "Woohoo!"]
    static let missed = ["Almost!", "Keep going!", "You'll get it!", "Good try!"]

    /// A headline and emoji for the end of a session, by how it went.
    static func finish(correct: Int, total: Int) -> (emoji: String, title: String) {
        guard total > 0 else { return ("🎉", "All Done!") }
        let score = Double(correct) / Double(total)
        switch score {
        case 1: return ("🏆", "Perfect!")
        case 0.8...: return ("🌟", "Amazing!")
        case 0.5...: return ("🎉", "Great Job!")
        default: return ("💪", "Nice Work!")
        }
    }

    /// Stars out of three for a session.
    static func stars(correct: Int, total: Int) -> Int {
        guard total > 0 else { return 3 }
        let score = Double(correct) / Double(total)
        return score >= 0.9 ? 3 : score >= 0.6 ? 2 : 1
    }
}

// MARK: - Buttons

/// Big, chunky, squishy: a press shrinks the button a little and it springs
/// back, which reads as "tappable" to a small child.
struct ChunkyButtonStyle: ButtonStyle {
    var fill: AnyShapeStyle
    var foreground: Color = .white

    init<S: ShapeStyle>(_ fill: S, foreground: Color = .white) {
        self.fill = AnyShapeStyle(fill)
        self.foreground = foreground
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(configuration.isPressed ? 0.05 : 0.15), radius: configuration.isPressed ? 2 : 6, y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// The squish without any chrome, for tiles that draw their own background.
struct SquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Confetti

/// A one-shot burst of confetti. Change `trigger` to fire it again.
struct ConfettiView: View {
    var trigger: Int
    var colors: [Color] = DeckPalette.allCases.map(\.top)

    private struct Piece {
        let x: Double, drift: Double, speed: Double, spin: Double, size: Double, delay: Double
        let color: Color
        let isCircle: Bool
    }

    @State private var pieces: [Piece] = []
    @State private var start = Date.distantPast
    @State private var running = false

    private let duration = 2.6

    var body: some View {
        TimelineView(.animation(paused: !running)) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                guard elapsed < duration + 0.5 else { return }
                for piece in pieces {
                    let t = elapsed - piece.delay
                    guard t > 0 else { continue }
                    let y = -20 + piece.speed * t + 260 * t * t
                    let x = piece.x * size.width + piece.drift * t * 60 + sin(t * 4 + piece.spin) * 12
                    guard y < size.height + 20 else { continue }
                    let fade = max(0, min(1, (duration - t) / 0.6))
                    var copy = context
                    copy.opacity = fade
                    copy.translateBy(x: x, y: y)
                    copy.rotate(by: .radians(piece.spin + t * 6))
                    let rect = CGRect(x: -piece.size / 2, y: -piece.size / 4, width: piece.size, height: piece.size / 2)
                    let shape = piece.isCircle ? Path(ellipseIn: rect.insetBy(dx: piece.size / 4, dy: 0)) : Path(rect)
                    copy.fill(shape, with: .color(piece.color))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger, initial: true) { _, value in
            guard value > 0 else { return }
            pieces = (0..<90).map { _ in
                Piece(x: .random(in: 0...1), drift: .random(in: -1...1), speed: .random(in: 60...220),
                      spin: .random(in: 0...(2 * .pi)), size: .random(in: 8...14), delay: .random(in: 0...0.35),
                      color: colors.randomElement() ?? .pink, isCircle: Bool.random())
            }
            start = .now
            running = true
            Task {
                try? await Task.sleep(for: .seconds(duration + 0.6))
                if Date.now.timeIntervalSince(start) >= duration + 0.5 { running = false }
            }
        }
    }
}

// MARK: - Backgrounds

/// A soft wash of a deck's colour behind a study screen.
struct DeckBackdrop: View {
    let palette: DeckPalette

    var body: some View {
        LinearGradient(colors: [palette.top.opacity(0.22), palette.bottom.opacity(0.08), Color(.systemBackground)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

// MARK: - Picking the app's colour

/// A tiny copy of the app icon in a theme's colour, for the picker.
struct ThemeIconPreview: View {
    let theme: AppTheme
    var picture: AppIconPicture = .aPlus

    var body: some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(theme.gradient)
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.white.opacity(0.45))
                        .frame(width: 29, height: 20)
                        .rotationEffect(.degrees(12))
                        .offset(x: -6, y: -4)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(.white)
                        .frame(width: 31, height: 22)
                        .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                        .overlay { cardPicture }
                        .rotationEffect(.degrees(-7))
                        .offset(x: 1, y: 5)
                    Image(systemName: "sparkle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.sparkleColor)
                        .offset(x: 16, y: -15)
                }
            }
            .overlay {
                // A hint of the glass rim the real icon has.
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
            }
            .frame(width: 54, height: 54)
            .shadow(color: theme.bottom.opacity(0.35), radius: 4, y: 2)
    }

    @ViewBuilder
    private var cardPicture: some View {
        switch picture {
        case .aPlus:
            Text("A+")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(theme.bottom)
        case .hundred:
            VStack(spacing: 0.5) {
                Text("100")
                    .font(.system(size: 9.5, weight: .black, design: .rounded))
                Capsule().frame(width: 17, height: 1.6)
                Capsule().frame(width: 14, height: 1.6)
            }
            .foregroundStyle(theme.bottom)
            .rotationEffect(.degrees(6))
        }
    }
}

/// "Pick your colour": tints the app, recolours the widget, and swaps the
/// Home Screen icon to match — in the colour and with the grade picked here.
struct ThemePicker: View {
    @AppStorage(AppTheme.storageKey, store: AppTheme.defaults) private var themeRaw = AppTheme.classic.rawValue
    @AppStorage(AppIconPicture.storageKey, store: AppTheme.defaults) private var pictureRaw = AppIconPicture.aPlus.rawValue

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .classic }
    private var picture: AppIconPicture { AppIconPicture(rawValue: pictureRaw) ?? .aPlus }

    var body: some View {
        VStack(spacing: 14) {
            Picker("Icon picture", selection: Binding(get: { picture }, set: { apply(theme, $0) })) {
                ForEach(AppIconPicture.allCases) { option in
                    Text(option.name).tag(option)
                }
            }
            .pickerStyle(.segmented)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 14) {
                ForEach(AppTheme.allCases) { option in
                    let selected = option == theme
                    Button {
                        apply(option, picture)
                    } label: {
                        VStack(spacing: 5) {
                            ThemeIconPreview(theme: option, picture: picture)
                                .overlay(alignment: .bottomTrailing) {
                                    if selected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .green)
                                            .offset(x: 6, y: 6)
                                    }
                                }
                            Text(option.name)
                                .font(.caption2.weight(selected ? .bold : .regular))
                                .foregroundStyle(selected ? .primary : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .buttonStyle(SquishButtonStyle())
                    .accessibilityLabel(option.name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func apply(_ newTheme: AppTheme, _ newPicture: AppIconPicture) {
        themeRaw = newTheme.rawValue
        pictureRaw = newPicture.rawValue
        WidgetCenter.shared.reloadAllTimelines()
        let app = UIApplication.shared
        let icon = newTheme.iconName(with: newPicture)
        guard app.supportsAlternateIcons, app.alternateIconName != icon else { return }
        app.setAlternateIconName(icon) { _ in }
    }
}

// MARK: - Shake

/// A quick side-to-side wobble for a wrong answer. Animate `progress` from 0
/// to 1 to shake twice.
struct ShakeEffect: GeometryEffect {
    var progress: CGFloat
    var travel: CGFloat = 7

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(progress * .pi * 4), y: 0))
    }
}

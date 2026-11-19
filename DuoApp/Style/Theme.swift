import SwiftUI

/// The app's look: near-black, brushed silver and one racing red, taken from the app icon.
/// Every colour and type rule lives here; views never hard-code them.
/// Nothing in here is main-actor isolated: `Color` is Sendable, and the helpers are plain functions.
enum Theme {
    // MARK: Colours

    static let background = rgb(0x0A, 0x0A, 0x0B)
    static let surface = rgb(0x15, 0x15, 0x17)
    static let raised = rgb(0x1E, 0x1E, 0x21)
    static let hairline = rgb(0x2A, 0x2A, 0x2E)

    static let textPrimary = rgb(0xE9, 0xE9, 0xEC)
    static let textSecondary = rgb(0x9A, 0x9A, 0xA2)
    static let textTertiary = rgb(0x66, 0x66, 0x6D)

    /// Racing red. For the live badge, progress bars, selection, toggles and primary buttons.
    /// Never for small body text (about 4.3:1 on the background).
    static let accent = rgb(0xEC, 0x00, 0x14)

    /// Corner radius of tiles and rows.
    static let cornerRadius: CGFloat = 10

    // MARK: Timing

    /// Flags on the track map: yellow sectors, safety car and VSC (Android's colours).
    static let flagYellow = rgb(0xFF, 0xD6, 0x0A)
    /// A red flag on the track map.
    static let flagRed = rgb(0xFF, 0x3B, 0x30)
    /// The dark casing under the map's outline, and the ring round each car dot.
    static let mapCasing = Color(red: 0, green: 0, blue: 0, opacity: 0.85)
    /// Floating panels sit over the video at this opacity.
    static let panelOpacity = 0.9

    /// The fastest of all (lap or sector), F1's purple.
    static let timingPurple = rgb(0xB1, 0x4A, 0xED)
    /// A personal best (lap or sector), F1's green.
    static let timingGreen = rgb(0x30, 0xD1, 0x58)
    /// Tyre compounds, as F1 rings them: soft, medium, hard, intermediate, wet.
    static let tyreSoft = rgb(0xDA, 0x29, 0x1C)
    static let tyreMedium = rgb(0xFF, 0xD1, 0x2E)
    static let tyreHard = rgb(0xF0, 0xF0, 0xEC)
    static let tyreIntermediate = rgb(0x43, 0xB0, 0x2A)
    static let tyreWet = rgb(0x00, 0x67, 0xAD)

    /// A team colour from F1's "RRGGBB"; secondary silver when it is missing or unreadable.
    static func teamColour(_ hex: String) -> Color {
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return textSecondary }
        return rgb((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}

// MARK: - Text styles (Dynamic Type text styles only)

extension Text {
    /// Bold, condensed, primary silver. Screen and row headings.
    func heading(_ style: Font.TextStyle = .title3) -> Text {
        font(.system(style)).bold().fontWidth(.condensed).foregroundStyle(Theme.textPrimary)
    }

    /// Bold, condensed row and tile titles.
    func rowTitle(_ style: Font.TextStyle = .body) -> Text {
        font(.system(style)).bold().fontWidth(.condensed).foregroundStyle(Theme.textPrimary)
    }

    /// Small, uppercase, condensed with a little tracking.
    func sectionLabel() -> some View {
        font(.caption).fontWidth(.condensed).tracking(1).foregroundStyle(Theme.textSecondary)
            .textCase(.uppercase)
    }

    /// The red LIVE capsule: white, bold, condensed.
    func liveBadge() -> some View {
        font(.caption).bold().fontWidth(.condensed).foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.accent, in: Capsule())
    }
}

// MARK: - Surfaces

extension View {
    /// A surface card with 10 pt continuous corners.
    func card() -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        return background(Theme.surface, in: shape).clipShape(shape)
    }

    /// The app background, behind everything (also under the safe areas).
    func themedBackground() -> some View {
        background(Theme.background)
    }
}

// MARK: - Glass (Apple design pass)

extension View {
    /// Clear glass with a light dark layer under it, for small labels and controls over the video:
    /// Apple puts clear glass over media and dims it so text stays readable on a bright picture.
    func videoGlass<S: Shape>(in shape: S) -> some View {
        glassEffect(.clear.tint(Color.black.opacity(0.35)), in: shape)
    }
}

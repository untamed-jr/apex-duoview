import SwiftUI

// The data layouts' regions (`LayoutEngine.dataRegions`), drawn in place by the multiview: the
// map with its header controls, the tower, and until the next build the Race Engineer console
// and the Scrub Deck as labelled placeholders (the beta.2 rule: space kept for later is drawn and
// labelled). Each is placed by the multiview with `.frame` and `.position`, like a tile, so a
// layout or fold change glides the same view to its new frame.

/// The map in a data layout: the floating panel's header controls (Battle, −1 s / +1 s, ⟲ ⟳)
/// over the map. No title, close or drag: the layout owns its place.
struct DockedMapPanel: View {
    let timing: TimingController
    let onCar: @MainActor (String) -> Void

    var body: some View {
        DataRegionFrame {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    MapPanelControls(timing: timing, onCar: onCar)
                }
                .padding(.horizontal, 2)
                .frame(height: 34)
                .background(Theme.raised)
                MapPanel(timing: timing, onCar: onCar)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map")
    }
}

/// The tower in a data layout: header, column titles and rows, its columns fitted to the region.
struct DockedTowerPanel: View {
    let timing: TimingController
    let onCar: @MainActor (String) -> Void

    var body: some View {
        DataRegionFrame {
            TowerView(timing: timing, onCar: onCar)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tower")
    }
}

/// A region kept for the next build, drawn and labelled: a dashed outline with its caption. Not
/// interactive, so a tap on it reaches the background (and shows or hides the controls).
struct DataRegionPlaceholder: View {
    static let raceEngineer = "Race Engineer \u{2014} next build"
    static let scrubDeck = "Scrub Deck \u{2014} next build"

    let caption: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            Text(caption)
                .font(.subheadline)
                .fontWidth(.condensed)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(16)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

/// The look the map and tower regions share: the floating panels' surface and hairline, fully
/// opaque (nothing is under it).
private struct DataRegionFrame<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        content
            .background(Theme.surface, in: shape)
            .clipShape(shape)
            .overlay { shape.strokeBorder(Theme.hairline, lineWidth: 1).allowsHitTesting(false) }
            .contentShape(shape)
    }
}

/// Laptop with one feed and no timing: a quiet line in the bottom half (where beta.2's placeholder
/// was) rather than a blank screen. "Loading timing…" while the timing loads (or is tried again
/// after a failure), "No timing for this session" when there is none; nothing before the player
/// has attached the timing (the opening spinner shows then). Its own view, so only it follows the
/// timing's status. Not interactive.
struct LaptopTimingNote: View {
    static let loading = "Loading timing\u{2026}"

    let timing: TimingController

    var body: some View {
        Group {
            if let text = Self.text(timing.status) {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    static func text(_ status: TimingStatus) -> String? {
        switch status {
        case .idle: return nil
        case .loading: return loading
        case .unavailable(let reason):
            return reason == TimingController.retrying ? loading : TimingController.noTiming
        // The data layouts take over once the timing is in; nothing to say here.
        case .ready, .estimated: return nil
        }
    }
}

import LiveTiming
import SwiftUI

/// The map and the tower as panels over the video, in any fold and layout, and over the
/// single-feed player. The "Map" control (`TimingMapButton`) turns both on or off; each has its
/// own ✕. A panel moves by its header, resizes from its corner handle or with a pinch, sits at
/// 0.9 opacity, and is remembered per posture and screen shape (`PanelLayout.postureKey`).
///
/// Only the panels take touches: the space around them reaches the feeds underneath. Nothing
/// shows for content without timing. A panel the multiview's data layout already shows in its
/// own region (`TimingController.dockedPanels`) hides while it does, and comes back with the
/// next layout.
///
/// The tower adapts its columns to its width (`TowerColumns`), so a narrowed panel keeps the
/// position, code and gap.
struct FloatingPanels: View {
    let timing: TimingController
    /// Where the panels may sit, in this view's own space (the safe area).
    let bounds: CGRect
    let postureKey: String
    /// A car was tapped on the map or the tower, or the map's Battle chip (its racing number):
    /// opens its onboard.
    let onCar: @MainActor (String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if timing.showsData {
                if timing.showsFloating(.tower) {
                    FloatingPanel(
                        panel: .tower, title: "Tower", settings: timing.settings, bounds: bounds, postureKey: postureKey,
                        onClose: { timing.closePanel(.tower) }
                    ) {
                        EmptyView()
                    } content: {
                        TowerView(timing: timing, onCar: onCar)
                    }
                }
                if timing.showsFloating(.map) {
                    FloatingPanel(
                        panel: .map, title: "Map", settings: timing.settings, bounds: bounds, postureKey: postureKey,
                        onClose: { timing.closePanel(.map) }
                    ) {
                        MapPanelControls(timing: timing, onCar: onCar)
                    } content: {
                        MapPanel(timing: timing, onCar: onCar)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One floating panel: a header (title, the panel's own controls, ✕) that drags it, its content,
/// and a corner handle that resizes it; a pinch anywhere on it scales it. Frames are kept inside
/// `bounds` (`PanelLayout`) and saved per posture key when a gesture ends.
struct FloatingPanel<Accessory: View, Content: View>: View {
    let panel: TimingPanel
    let title: String
    let settings: TimingSettings
    let bounds: CGRect
    let postureKey: String
    let onClose: @MainActor () -> Void
    let accessory: Accessory
    let content: Content

    /// The saved frame for this posture key (nil: never moved, so the default).
    @State private var stored: CGRect?
    /// The gestures in progress.
    @State private var drag: CGSize = .zero
    @State private var resize: CGSize = .zero
    @State private var pinch: CGFloat = 1

    init(panel: TimingPanel, title: String, settings: TimingSettings, bounds: CGRect, postureKey: String,
         onClose: @escaping @MainActor () -> Void,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.panel = panel
        self.title = title
        self.settings = settings
        self.bounds = bounds
        self.postureKey = postureKey
        self.onClose = onClose
        self.accessory = accessory()
        self.content = content()
        // Seeded here, so a panel shows at its saved place from its first frame (no jump).
        _stored = State(initialValue: settings.panelFrame(panel.rawValue, posture: postureKey))
    }

    /// Where it rests: saved, or the default, kept on screen.
    private var base: CGRect {
        PanelLayout.clamped(stored ?? PanelLayout.defaultFrame(panel, in: bounds), in: bounds)
    }

    /// Where it shows, with the gestures in progress.
    private var shown: CGRect {
        let moved = PanelLayout.moved(base, by: drag, in: bounds)
        let sized = PanelLayout.resized(moved, by: resize, in: bounds)
        return PanelLayout.scaled(sized, by: pinch, in: bounds)
    }

    var body: some View {
        let frame = shown
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .frame(width: frame.width, height: frame.height)
        .background(Theme.surface, in: shape)
        .clipShape(shape)
        .overlay(alignment: .bottomTrailing) { resizeHandle }
        .overlay { shape.strokeBorder(Theme.hairline, lineWidth: 1).allowsHitTesting(false) }
        .contentShape(shape)
        .opacity(Theme.panelOpacity)
        .gesture(
            MagnifyGesture()
                .onChanged { value in pinch = value.magnification }
                .onEnded { value in
                    commit(PanelLayout.scaled(base, by: value.magnification, in: bounds))
                    pinch = 1
                })
        .position(x: frame.midX, y: frame.midY)
        .onChange(of: postureKey) { _, _ in load() }
    }

    private var header: some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .bold()
                .fontWidth(.condensed)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .layoutPriority(-1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            accessory
            PanelIconButton(systemImage: "xmark", accessibility: "Close \(title)") { onClose() }
        }
        .padding(.leading, 10)
        .padding(.trailing, 2)
        .frame(height: 34)
        .background(Theme.raised)
        .contentShape(Rectangle())
        // Global space: the panel moves under the finger, so local translations would feed back.
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in drag = value.translation }
                .onEnded { value in
                    commit(PanelLayout.moved(base, by: value.translation, in: bounds))
                    drag = .zero
                })
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption2.bold())
            .foregroundStyle(Theme.textSecondary)
            .padding(5)
            .background(Theme.raised, in: Circle())
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in resize = value.translation }
                    .onEnded { value in
                        commit(PanelLayout.resized(base, by: value.translation, in: bounds))
                        resize = .zero
                    })
            .accessibilityHidden(true)
    }

    private func load() {
        stored = settings.panelFrame(panel.rawValue, posture: postureKey)
    }

    private func commit(_ frame: CGRect) {
        stored = frame
        settings.setPanelFrame(frame, panel: panel.rawValue, posture: postureKey)
    }
}

/// The "Map" control, in the multiview's top bar and over the single-feed player: shows both
/// panels, or hides them. Only for content with timing, and hidden while the multiview's data
/// layout already shows both the map and the tower (its floating panels would stay hidden).
struct TimingMapButton: View {
    let timing: TimingController
    let onInteraction: @MainActor () -> Void

    var body: some View {
        if timing.showsData, !timing.dockedPanels.isSuperset(of: TimingPanel.allCases) {
            let showing = !timing.panels.isEmpty
            Button {
                onInteraction()
                timing.toggleMapPanels()
            } label: {
                MultiviewChromeLabel(title: "Map", systemImage: showing ? "map.fill" : "map")
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(showing ? "Hide the map" : "Show the map")
        }
    }
}

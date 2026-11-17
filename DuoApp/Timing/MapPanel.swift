import LiveTiming
import SwiftUI

/// The map panel's body: the track map at picture time, or why there is none yet; in a race, the
/// pit circle instead when the header's switch says so (`PitCircleView`). Its header controls
/// (Map / Pit circle, −1 s / +1 s, ⟲ ⟳) are `MapPanelControls`, in the floating panel's header
/// and over the docked map. The note over the top: a live status line, "Timing catching up", or
/// "Timing estimated — nudge until the cars match" (`TimingController.mapNote`).
struct MapPanel: View {
    let timing: TimingController
    /// A car's dot was tapped (its racing number): opens its onboard. Holding a dot shows its pit
    /// window (races).
    let onCar: @MainActor (String) -> Void
    /// Race Engineer's mini map: only this car (a racing number) is drawn in full, the others as
    /// small grey dots. Nil for the full map.
    var highlight: String? = nil

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if let note = timing.mapNote {
                    MapPanelNote(text: note)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch timing.status {
        case .ready, .estimated:
            if highlight == nil, timing.isRace, timing.mapMode == .pitCircle {
                PitCircleView(timing: timing)
            } else if let map = timing.map {
                MapCanvas(timing: timing, map: map, turn: timing.mapTurn, highlight: highlight, onCar: onCar)
            } else if let message = timing.mapMessage {
                MapPanelMessage(text: message, busy: false)
            } else {
                MapPanelMessage(text: "Loading the map…", busy: true)
            }
        case .loading:
            MapPanelMessage(text: timing.loadingText, busy: true)
        case .unavailable(let reason):
            MapPanelMessage(text: reason, busy: false)
        case .idle:
            Color.clear
        }
    }
}

/// The header's controls: the Battle chip while your driver is in a battle, the offset with
/// −1 s / +1 s, and the turn (⟲ ⟳, with Reset once turned).
struct MapPanelControls: View {
    let timing: TimingController
    /// The Battle chip was tapped: the rival's racing number, to open their onboard.
    let onCar: @MainActor (String) -> Void

    var body: some View {
        let circle = timing.isRace && timing.mapMode == .pitCircle
        HStack(spacing: 0) {
            if let rival = timing.battleRival {
                BattleChip(rival: rival) { onCar(rival.number) }
            }
            if timing.isRace {
                // Map / Pit circle: names the other view.
                PanelTextButton(title: circle ? "Map" : "Pit circle",
                                accessibility: circle ? "Show the map" : "Show the pit circle") {
                    timing.setMapMode(circle ? .map : .pitCircle)
                }
            }
            PanelTextButton(title: "\u{2212}1 s", accessibility: "Timing one second earlier") { timing.nudge(-1) }
            Text(OffsetText.text(timing.offsetMs))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel("Timing offset \(OffsetText.text(timing.offsetMs))")
            PanelTextButton(title: "+1 s", accessibility: "Timing one second later") { timing.nudge(1) }
            // The circle doesn't turn: the finish is always at the top.
            if !circle {
                PanelIconButton(systemImage: "rotate.left", accessibility: "Turn the map left") {
                    timing.turnMap(by: -TimingController.turnStep)
                }
                PanelIconButton(systemImage: "rotate.right", accessibility: "Turn the map right") {
                    timing.turnMap(by: TimingController.turnStep)
                }
            }
            if !circle, timing.mapTurn != 0 {
                PanelIconButton(systemImage: "arrow.uturn.backward", accessibility: "Reset the map's turn") {
                    timing.resetMapTurn()
                }
            }
        }
    }
}

/// "Battle" on the map's header: your driver is within 1.0 s of the car ahead or behind. Tapping it
/// opens the rival's onboard.
private struct BattleChip: View {
    let rival: BattleRival
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Text("Battle")
                .font(.caption2)
                .bold()
                .fontWidth(.condensed)
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.flagYellow, in: Capsule())
                .frame(minHeight: 32)
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Battle with \(rival.tla)")
        .accessibilityHint("Opens \(rival.tla)'s onboard")
    }
}

/// The flags caption ("Safety car", "Red flag · Q3 resumes in 4:12"), from the same frame's
/// `MapState` as the outline, so the two never disagree (after a seek, say).
private struct MapCaption: View {
    let caption: String?
    let red: Bool

    var body: some View {
        if let caption {
            Text(caption)
                .font(.caption)
                .bold()
                .fontWidth(.condensed)
                .foregroundStyle(red ? Theme.flagRed : Theme.flagYellow)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.background.opacity(0.8), in: Capsule())
                .padding(.bottom, 6)
                .allowsHitTesting(false)
        }
    }
}

/// A line over the top of the map ("Timing estimated — nudge until the cars match"), or a held
/// car's pit window over its foot.
struct MapPanelNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Theme.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.background.opacity(0.8), in: Capsule())
            .padding(.top, 6)
            .padding(.horizontal, 6)
            .allowsHitTesting(false)
    }
}

/// Instead of the map (or the pit circle): loading, or why there is none.
struct MapPanelMessage: View {
    let text: String
    let busy: Bool

    var body: some View {
        VStack(spacing: 8) {
            if busy {
                ProgressView().tint(Theme.textSecondary)
            }
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
    }
}

/// The map itself. The fit (auto-rotation, scale) and everything that doesn't move are worked
/// out when the size or the turn changes; each frame of the `TimelineView` (which stops while the
/// panel is gone) reads only picture time and the cars. The renderer captures plain values only.
private struct MapCanvas: View {
    let timing: TimingController
    let map: TrackMap
    let turn: Double
    let highlight: String?
    let onCar: @MainActor (String) -> Void

    /// A held car's pit window, shown for a few seconds after the hold.
    @State private var held: HeldWindow?
    /// A hold is under way (or just ended): the tap SwiftUI may still deliver when the finger
    /// lifts must not open the held car's onboard.
    @State private var holding = false

    private struct HeldWindow: Equatable {
        let id = UUID()
        let number: String
        let text: String
    }

    /// How long a held car's pit window stays.
    static let heldSeconds = 4.0

    var body: some View {
        GeometryReader { proxy in
            let transform = map.geometry.fit(in: proxy.size, inset: MapDrawing.inset, userTurnDegrees: turn)
            let projected = ProjectedMap(map: map, transform: transform)
            TimelineView(.animation) { context in
                let state: MapState = timing.pictureTime.map { timing.mapState(at: $0) } ?? .empty
                let phase = context.date.timeIntervalSinceReferenceDate
                Canvas { graphics, _ in
                    MapDrawing.draw(in: &graphics, projected: projected, state: state, transform: transform, phase: phase,
                                    highlight: highlight)
                }
                .overlay(alignment: .bottom) {
                    VStack(spacing: 4) {
                        if let held {
                            MapPanelNote(text: held.text)
                        }
                        MapCaption(caption: state.caption, red: state.flags.status == .red)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                tapped(at: location, transform: transform)
            }
            // Holding a car (races): its pit window.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onChanged { value in
                        if case .second(true, let drag?) = value {
                            holding = true
                            hold(at: drag.startLocation, transform: transform)
                        }
                    }
                    .onEnded { _ in
                        releaseHold()
                    })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(map.traced ? "Track map, traced from the cars" : "Track map")
        }
        .task(id: held) {
            guard held != nil else { return }
            try? await Task.sleep(for: .seconds(Self.heldSeconds))
            if !Task.isCancelled { held = nil }
        }
    }

    /// The car whose dot is within 22 pt of `location` (a 44 pt target), at this moment.
    private func car(at location: CGPoint, transform: MapTransform) -> String? {
        guard let t = timing.pictureTime else { return nil }
        let dots = timing.mapState(at: t).cars.map { (number: $0.number, at: transform.point($0.point)) }
        return MapHitTest.car(at: location, among: dots)
    }

    private func tapped(at location: CGPoint, transform: MapTransform) {
        guard !holding else { return }
        if let number = car(at: location, transform: transform) { onCar(number) }
    }

    /// Lets taps through again a moment after a hold ends (after any tap it brings).
    private func releaseHold() {
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            holding = false
        }
    }

    private func hold(at location: CGPoint, transform: MapTransform) {
        // The gesture reports every move of the finger: one reading per car held.
        guard let number = car(at: location, transform: transform), held?.number != number,
              let text = timing.pitWindowText(car: number) else { return }
        held = HeldWindow(number: number, text: text)
    }
}

/// Draws one frame of the map: Android's look in the app's dark style. Plain values in, no actor.
enum MapDrawing {
    /// Room kept round the outline for the dots' codes and the corner numbers.
    static let inset: CGFloat = 26
    static let dotRadius: CGFloat = 6
    static let dimmedDotRadius: CGFloat = 4.5

    static func draw(in graphics: inout GraphicsContext, projected: ProjectedMap, state: MapState,
                     transform: MapTransform, phase: Double, highlight: String? = nil) {
        guard projected.outline.count >= 2 else { return }
        let round = StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
        var track = Path()
        track.addLines(projected.outline)
        track.closeSubpath()
        // A dark wide stroke under a light thin one; yellow under a safety car or VSC (pulsing as
        // it ends), red under a red flag.
        graphics.stroke(track, with: .color(Theme.mapCasing), style: round)
        graphics.stroke(track, with: .color(outlineColour(state.flags.status, phase: phase)),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

        // Yellow marshal sectors; double yellow drawn thicker.
        for (sector, level) in state.flags.yellowSectors {
            let index = sector - 1
            guard projected.sectors.indices.contains(index), projected.sectors[index].count >= 2 else { continue }
            var path = Path()
            path.addLines(projected.sectors[index])
            graphics.stroke(path, with: .color(Theme.flagYellow),
                            style: StrokeStyle(lineWidth: level >= 2 ? 6 : 3.5, lineCap: .round, lineJoin: .round))
        }

        // The chequered start/finish line, START ahead of it and FINISH behind.
        if let line = projected.startLine {
            var path = Path()
            path.move(to: line.from)
            path.addLine(to: line.to)
            graphics.stroke(path, with: .color(.white), lineWidth: 4)
            graphics.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 4, dash: [2, 2]))
        }
        if let at = projected.startLabel {
            graphics.draw(label("START"), at: at)
        }
        if let at = projected.finishLabel {
            graphics.draw(label("FINISH"), at: at)
        }

        for corner in projected.corners {
            graphics.draw(Text(corner.text).font(.caption2).fontWidth(.condensed).foregroundStyle(Theme.textTertiary),
                          at: corner.at)
        }

        if let highlight {
            // The mini map: every other car a small grey dot, this one on top with a white ring.
            for car in state.cars where car.number != highlight {
                drawBackgroundCar(car, in: &graphics, transform: transform)
            }
            for car in state.cars where car.number == highlight {
                drawCar(car, in: &graphics, transform: transform, ringed: true)
            }
        } else {
            for car in state.cars {
                drawCar(car, in: &graphics, transform: transform)
            }
        }

        if let safetyCar = state.safetyCar {
            let p = transform.point(safetyCar)
            let r: CGFloat = 7
            let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            graphics.fill(dot, with: .color(Theme.flagYellow))
            graphics.stroke(dot, with: .color(Theme.mapCasing), lineWidth: 1.5)
            graphics.draw(Text("SC").font(.system(size: 7, weight: .heavy)).foregroundStyle(Color.black), at: p)
        }
    }

    private static func drawCar(_ car: MapCar, in graphics: inout GraphicsContext, transform: MapTransform,
                                ringed: Bool = false) {
        let p = transform.point(car.point)
        let r = car.dimmed ? dimmedDotRadius : dotRadius
        let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        let colour = Theme.teamColour(car.colour)
        graphics.fill(dot, with: .color(car.dimmed ? colour.opacity(0.45) : colour))
        graphics.stroke(dot, with: .color(Theme.mapCasing), lineWidth: 1.5)
        if ringed {
            let ring = r + 3
            graphics.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: 2 * ring, height: 2 * ring)),
                            with: .color(Color.white), lineWidth: 2)
        }
        if car.flyingRing {
            let ring = r + 2.5
            graphics.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: 2 * ring, height: 2 * ring)),
                            with: .color(Theme.flagYellow), lineWidth: 1.5)
        }
        let code = Text(car.tla)
            .font(.caption2)
            .bold()
            .fontWidth(.condensed)
            .foregroundStyle(car.dimmed ? Theme.textTertiary : Theme.textPrimary)
        graphics.draw(code, at: CGPoint(x: p.x + r + 2, y: p.y), anchor: .leading)
    }

    /// A car other than the mini map's own: a small grey dot, no code.
    private static func drawBackgroundCar(_ car: MapCar, in graphics: inout GraphicsContext, transform: MapTransform) {
        let p = transform.point(car.point)
        let r: CGFloat = 3
        graphics.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                      with: .color(Theme.textTertiary.opacity(car.dimmed ? 0.4 : 0.8)))
    }

    private static func label(_ text: String) -> Text {
        Text(text).font(.caption2).fontWidth(.compressed).foregroundStyle(Theme.textSecondary)
    }

    static func outlineColour(_ status: TrackStatusKind, phase: Double) -> Color {
        switch status {
        case .clear, .yellow:
            return Theme.textPrimary
        case .red:
            return Theme.flagRed
        case .safetyCar, .vsc:
            return Theme.flagYellow
        case .safetyCarInThisLap, .vscEnding:
            // Pulses about once a second as it ends.
            let wave = 0.5 + 0.5 * sin(phase * 2 * Double.pi / 1.2)
            return Theme.flagYellow.opacity(0.4 + 0.6 * wave)
        }
    }
}

// MARK: - Panel header buttons

/// A small text button for a panel's header ("−1 s"), with a 32 pt target.
struct PanelTextButton: View {
    let title: String
    let accessibility: String
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Text(title)
                .font(.caption)
                .bold()
                .fontWidth(.condensed)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 4)
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }
}

/// A small symbol button for a panel's header (⟲ ⟳ ✕), with a 32 pt target.
struct PanelIconButton: View {
    let systemImage: String
    let accessibility: String
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.caption.bold())
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 30, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }
}

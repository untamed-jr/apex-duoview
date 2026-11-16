import LiveTiming
import SwiftUI

/// The map panel's body: the track map at picture time, or why there is none yet. Its header
/// controls (−1 s / +1 s, ⟲ ⟳) are `MapPanelControls`, in the floating panel's header.
struct MapPanel: View {
    let timing: TimingController
    /// A car's dot was tapped (its racing number). Opens its onboard from build 12.
    let onCar: @MainActor (String) -> Void

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if timing.status == .estimated {
                    MapPanelNote(text: TimingController.estimatedNote)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch timing.status {
        case .ready, .estimated:
            if let map = timing.map {
                MapCanvas(timing: timing, map: map, turn: timing.mapTurn, onCar: onCar)
            } else if let message = timing.mapMessage {
                MapPanelMessage(text: message, busy: false)
            } else {
                MapPanelMessage(text: "Loading the map…", busy: true)
            }
        case .loading:
            MapPanelMessage(text: "Loading timing…", busy: true)
        case .unavailable(let reason):
            MapPanelMessage(text: reason, busy: false)
        case .idle:
            Color.clear
        }
    }
}

/// The header's controls: the offset with −1 s / +1 s, and the turn (⟲ ⟳, with Reset once turned).
struct MapPanelControls: View {
    let timing: TimingController

    var body: some View {
        HStack(spacing: 0) {
            PanelTextButton(title: "\u{2212}1 s", accessibility: "Timing one second earlier") { timing.nudge(-1) }
            Text(OffsetText.text(timing.offsetMs))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel("Timing offset \(OffsetText.text(timing.offsetMs))")
            PanelTextButton(title: "+1 s", accessibility: "Timing one second later") { timing.nudge(1) }
            PanelIconButton(systemImage: "rotate.left", accessibility: "Turn the map left") {
                timing.turnMap(by: -TimingController.turnStep)
            }
            PanelIconButton(systemImage: "rotate.right", accessibility: "Turn the map right") {
                timing.turnMap(by: TimingController.turnStep)
            }
            if timing.mapTurn != 0 {
                PanelIconButton(systemImage: "arrow.uturn.backward", accessibility: "Reset the map's turn") {
                    timing.resetMapTurn()
                }
            }
        }
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

/// A line over the top of the map ("Timing estimated — nudge until the cars match").
private struct MapPanelNote: View {
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

/// Instead of the map: loading, or why there is none.
private struct MapPanelMessage: View {
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
    let onCar: @MainActor (String) -> Void

    var body: some View {
        GeometryReader { proxy in
            let transform = map.geometry.fit(in: proxy.size, inset: MapDrawing.inset, userTurnDegrees: turn)
            let projected = ProjectedMap(map: map, transform: transform)
            TimelineView(.animation) { context in
                let state: MapState = timing.pictureTime.map { timing.mapState(at: $0) } ?? .empty
                let phase = context.date.timeIntervalSinceReferenceDate
                Canvas { graphics, _ in
                    MapDrawing.draw(in: &graphics, projected: projected, state: state, transform: transform, phase: phase)
                }
                .overlay(alignment: .bottom) {
                    MapCaption(caption: state.caption, red: state.flags.status == .red)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                tapped(at: location, transform: transform)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(map.traced ? "Track map, traced from the cars" : "Track map")
        }
    }

    /// The car whose dot is within 22 pt of the tap (a 44 pt target), at this moment.
    private func tapped(at location: CGPoint, transform: MapTransform) {
        guard let t = timing.pictureTime else { return }
        let dots = timing.mapState(at: t).cars.map { (number: $0.number, at: transform.point($0.point)) }
        if let number = MapHitTest.car(at: location, among: dots) { onCar(number) }
    }
}

/// Draws one frame of the map: Android's look in the app's dark style. Plain values in, no actor.
enum MapDrawing {
    /// Room kept round the outline for the dots' codes and the corner numbers.
    static let inset: CGFloat = 26
    static let dotRadius: CGFloat = 6
    static let dimmedDotRadius: CGFloat = 4.5

    static func draw(in graphics: inout GraphicsContext, projected: ProjectedMap, state: MapState,
                     transform: MapTransform, phase: Double) {
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

        for car in state.cars {
            drawCar(car, in: &graphics, transform: transform)
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

    private static func drawCar(_ car: MapCar, in graphics: inout GraphicsContext, transform: MapTransform) {
        let p = transform.point(car.point)
        let r = car.dimmed ? dimmedDotRadius : dotRadius
        let dot = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        let colour = Theme.teamColour(car.colour)
        graphics.fill(dot, with: .color(car.dimmed ? colour.opacity(0.45) : colour))
        graphics.stroke(dot, with: .color(Theme.mapCasing), lineWidth: 1.5)
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

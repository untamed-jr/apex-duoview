import LiveTiming
import SwiftUI

/// The map panel's second view (races): the lap as a circle in time at the leader's pace, the
/// finish at the top and the cars clockwise, each as far round as its gap behind the leader
/// (`PitCircle`, Android's and MultiViewer's). Cars in the pit lane sit on the inner arc.
///
/// - Labels: the gap to the car ahead, or to the leader with the toggle ("Gaps: car ahead" /
///   "Gaps: leader").
/// - Tap or hold a car: every gap is measured to it and its pit window shows ("If HAM stops now,
///   out 2.1 s behind NOR"), with the arc a stop costs drawn behind it on the inside; tap it
///   again, or the empty middle, to let it go.
/// - Before the leader has finished a lap: "The circle starts once the leader has finished a
///   lap."; joined late, until the leader's next crossing: "The pit circle appears when the
///   leader next crosses the line."
///
/// The state (`TimingController.pitCircle`) is built at the 2 Hz tick, never per frame; this
/// view only draws it. The renderer captures plain values only.
struct PitCircleView: View {
    let timing: TimingController

    var body: some View {
        if let state = timing.pitCircle {
            if let circle = state.circle {
                PitCircleBoard(timing: timing, state: state, circle: circle)
            } else {
                MapPanelMessage(text: state.message ?? "", busy: false)
            }
        } else {
            MapPanelMessage(text: "Loading the pit circle\u{2026}", busy: true)
        }
    }
}

/// The circle with its toggle and its line underneath.
private struct PitCircleBoard: View {
    let timing: TimingController
    let state: PitCircleViewState
    let circle: PitCircleState

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Canvas { graphics, canvasSize in
                PitCircleDrawing.draw(in: &graphics, size: canvasSize, state: state, circle: circle)
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                let number = car(at: location, size: size)
                timing.selectPitCar(number, toggle: number != nil)
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onChanged { value in
                        if case .second(true, let drag?) = value, let number = car(at: drag.startLocation, size: size) {
                            timing.selectPitCar(number)
                        }
                    })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pit circle")
            .accessibilityValue(state.pitWindow ?? state.lossText ?? "")
        }
        .overlay(alignment: .topLeading) {
            Button {
                timing.setPitGapsToLeader(!state.toLeader)
            } label: {
                Text(state.toLeader ? "Gaps: leader" : "Gaps: car ahead")
                    .font(.caption2)
                    .bold()
                    .fontWidth(.condensed)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.raised, in: Capsule())
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(6)
            .accessibilityLabel(state.toLeader ? "Gaps to the leader" : "Gaps to the car ahead")
            .accessibilityHint("Switches the gap labels")
        }
        .overlay(alignment: .bottom) {
            if let line = state.pitWindow ?? state.lossText {
                Text(line)
                    .font(.caption)
                    .bold(state.pitWindow != nil)
                    .fontWidth(.condensed)
                    .foregroundStyle(state.pitWindow != nil ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.background.opacity(0.8), in: Capsule())
                    .padding(.bottom, 6)
                    .padding(.horizontal, 6)
                    .allowsHitTesting(false)
            }
        }
    }

    /// The car whose dot is within 22 pt of `location`.
    private func car(at location: CGPoint, size: CGSize) -> String? {
        let dots = PitCircleGeometry.dots(circle, width: Double(size.width), height: Double(size.height))
        return PitCircleGeometry.car(at: Double(location.x), Double(location.y), among: dots)
    }
}

/// Draws the pit circle. Plain values in, no actor.
enum PitCircleDrawing {
    static let dotRadius: CGFloat = 6

    static func draw(in graphics: inout GraphicsContext, size: CGSize, state: PitCircleViewState, circle: PitCircleState) {
        let width = Double(size.width), height = Double(size.height)
        let r = PitCircleGeometry.radius(width: width, height: height)
        let cx = width / 2, cy = height / 2
        func point(_ angle: Double, _ radius: Double) -> CGPoint {
            let p = PitCircleGeometry.point(angle: angle, radius: radius, cx: cx, cy: cy)
            return CGPoint(x: p.x, y: p.y)
        }

        // The track: a dark wide ring under a light thin one, and the pit lane inside it.
        let ring = Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        graphics.stroke(ring, with: .color(Theme.mapCasing), lineWidth: 9)
        graphics.stroke(ring, with: .color(Theme.textPrimary), lineWidth: 2)
        let lane = r * PitCircleGeometry.laneShare
        let laneRing = Path(ellipseIn: CGRect(x: cx - lane, y: cy - lane, width: 2 * lane, height: 2 * lane))
        graphics.stroke(laneRing, with: .color(Theme.textTertiary), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

        // The finish at the top, chequered across the ring.
        var finish = Path()
        finish.move(to: point(0, r - 9))
        finish.addLine(to: point(0, r + 9))
        graphics.stroke(finish, with: .color(.white), lineWidth: 4)
        graphics.stroke(finish, with: .color(.black), style: StrokeStyle(lineWidth: 4, dash: [2, 2]))

        // A stop's cost behind the selected car (else the leader), on the inside: where it would
        // come out.
        let reference = circle.cars.first { $0.number == (state.selected ?? circle.leader) }
        if let reference, circle.referenceLapMs > 0 {
            let span = min(Double(circle.pitLossMs) / Double(circle.referenceLapMs), 0.95) * 360
            var arc = Path()
            let steps = max(Int(span / 3), 2)
            for i in 0...steps {
                let angle = reference.angle - span * Double(i) / Double(steps)
                let p = point(angle, lane)
                if i == 0 { arc.move(to: p) } else { arc.addLine(to: p) }
            }
            graphics.stroke(arc, with: .color(Theme.flagYellow.opacity(0.7)),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            let out = point(reference.angle - span, lane)
            let tick = Path(ellipseIn: CGRect(x: out.x - 3, y: out.y - 3, width: 6, height: 6))
            graphics.fill(tick, with: .color(Theme.flagYellow))
        }

        // The cars, the leader last (on top), each with its code and gap outside the ring.
        for car in circle.cars.reversed() {
            let at = point(car.angle, car.inPit ? lane : r)
            let selected = car.number == state.selected
            let dot = Path(ellipseIn: CGRect(x: at.x - dotRadius, y: at.y - dotRadius, width: 2 * dotRadius, height: 2 * dotRadius))
            let colour = Theme.teamColour(car.teamColour)
            graphics.fill(dot, with: .color(car.inPit ? colour.opacity(0.5) : colour))
            graphics.stroke(dot, with: .color(Theme.mapCasing), lineWidth: 1.5)
            if selected {
                let ring = dotRadius + 3
                graphics.stroke(Path(ellipseIn: CGRect(x: at.x - ring, y: at.y - ring, width: 2 * ring, height: 2 * ring)),
                                with: .color(.white), lineWidth: 2)
            }
            let labelAt = point(car.angle, (car.inPit ? lane : r) + (car.inPit ? -18 : 20))
            let gap = state.label(car)
            let label = Text(gap == car.tla || gap.isEmpty ? car.tla : "\(car.tla)\n\(gap)")
                .font(.system(size: 9, weight: selected ? .heavy : .semibold))
                .foregroundStyle(car.inPit ? Theme.textTertiary : Theme.textPrimary)
            graphics.draw(label, at: labelAt, anchor: .center)
        }

        // The leader's lap in the middle.
        if let lap = circle.lap {
            graphics.draw(Text("Lap \(lap)").font(.caption).bold().foregroundStyle(Theme.textSecondary),
                          at: CGPoint(x: cx, y: cy), anchor: .center)
        }
    }
}

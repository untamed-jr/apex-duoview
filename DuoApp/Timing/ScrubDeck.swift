import LiveTiming
import SwiftUI

/// The Scrub Deck, on the laptop's bottom screen under the main feed: an event strip and, for
/// races and sprints, a lap chart (one line per driver, position by lap, your driver highlighted).
/// Qualifying and practice show only the strip, by time.
///
/// - The strip: lights out, pit stops (small ticks for everyone, a tall one for your driver),
///   safety car, VSC and red flag bands, each new fastest lap, retirements and the chequered flag;
///   team radio as small blue ticks hanging from the top (taller for your driver), behind the
///   fog like every marker.
/// - No spoilers: everything is drawn only up to picture time; the rest is an empty fog that
///   fills in as the race plays. "Show the whole race" (Settings › Track map) lifts it.
/// - Dragging anywhere previews a moment with its time (and lap, outside the fog); letting go moves
///   every feed there through the multiview's seek, once, as the scrubber does. In the fog the
///   moment is the video's own time, spread evenly to its end (no data past picture time).
/// - Tapping a marker or a radio tick jumps to 5 s before it. Tapping a line highlights that driver
///   and offers "Open onboard".
///
/// Its values come from `TimingController.deck` (2 Hz) and the main feed's timeline; times map
/// to the player's seconds with the inverse of picture time, as the timeline marks do.
struct ScrubDeck: View {
    let controller: MultiviewController
    /// "Open onboard": the highlighted driver's racing number.
    let onCar: @MainActor (String) -> Void

    var body: some View {
        DataRegionFrame {
            ScrubDeckContent(timing: controller.timing, controller: controller, onCar: onCar)
                .padding(8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scrub Deck")
    }
}

private struct ScrubDeckContent: View {
    let timing: TimingController
    let controller: MultiviewController
    let onCar: @MainActor (String) -> Void

    /// Where the finger is while it drags, as a fraction of the width.
    @State private var dragFraction: Double?
    /// The lap chart line tapped last (a racing number).
    @State private var selected: String?
    /// Design pass q7: the strip's PIT label grows with the iPhone's text size, up to the strip.
    @ScaledMetric(relativeTo: .caption2) private var textScale: CGFloat = 1

    static let headerHeight: CGFloat = 30
    static let raceStripHeight: CGFloat = 34
    static let timeStripHeight: CGFloat = 64
    /// Under the chart: the lap numbers.
    static let lapLabelHeight: CGFloat = 14
    /// A move this far is a drag, not a tap.
    static let dragThreshold: CGFloat = 6

    var body: some View {
        if let deck = timing.deck {
            let axis = DeckAxis.make(deck, timeline: controller.timeline)
            if axis.anchors.count >= 2 {
                deckBody(deck, axis: axis)
                    .overlay(alignment: .top) {
                        // Live, just before the join: the state on joining, labelled.
                        if let note = timing.catchUpNote {
                            TimingQuietLine(text: note)
                                .background(Theme.surface.opacity(0.9))
                        }
                    }
            } else {
                message("Waiting for the video\u{2026}")
            }
        } else if timing.timingHidden, let note = timing.catchUpNote {
            message(note)
        } else {
            message(timing.loadingText)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func deckBody(_ deck: DeckState, axis: DeckAxis) -> some View {
        let markers = DeckMarker.place(deck, axis: axis)
        // The clips at the deck's own moment (every clip with the whole race on), placed as markers.
        let radio = RadioModels.tickFractions(
            clips: timing.loadedSession?.radio ?? RadioClips(), pictureTime: deck.pictureTime,
            wholeRace: deck.wholeRace, favourite: deck.favourite,
            fraction: { axis.fraction(ofSeconds: deck.seconds(of: $0)) })
        return VStack(spacing: 4) {
            header(deck, axis: axis)
                .frame(height: Self.headerHeight)
            GeometryReader { proxy in
                let size = proxy.size
                let strip = Self.stripHeight(deck)
                let chart = CGSize(width: size.width, height: max(size.height - strip - Self.lapLabelHeight - 4, 0))
                let chosen = selected.flatMap { number in deck.rows.contains { $0.number == number } ? number : nil }
                let drag = dragFraction
                let scale = textScale
                Canvas { graphics, canvasSize in
                    DeckDrawing.draw(in: &graphics, size: canvasSize, deck: deck, axis: axis, markers: markers,
                                     stripHeight: strip, chartHeight: chart.height, selected: chosen, drag: drag,
                                     textScale: scale, radio: radio)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            let moved = abs(value.translation.width) + abs(value.translation.height)
                            if dragFraction != nil || moved > Self.dragThreshold {
                                dragFraction = Self.fraction(value.location.x, width: size.width)
                            }
                        }
                        .onEnded { value in
                            if let f = dragFraction {
                                dragFraction = nil
                                if let seconds = axis.seconds(atFraction: f) { controller.seek(toSeconds: seconds) }
                            } else {
                                tapped(at: value.location, deck: deck, axis: axis, markers: markers, radio: radio,
                                       width: size.width, strip: strip, chart: chart)
                            }
                        })
            }
            // The drawing is one element; the header (and its "Open onboard") stays reachable.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(deck.race ? "Lap chart and race events" : "Session events")
            .accessibilityValue(Self.spoken(markers))
            .accessibilityHint("Swipe up or down to move every feed 30 seconds")
            .accessibilityAdjustableAction { direction in
                let step: Double = direction == .increment ? 30 : -30
                controller.seek(toSeconds: controller.position + step)
            }
        }
    }

    /// While dragging: the moment's lap (outside the fog) and its time on the main feed. Otherwise
    /// the highlighted driver's "Open onboard", or how to use the deck.
    @ViewBuilder
    private func header(_ deck: DeckState, axis: DeckAxis) -> some View {
        HStack(spacing: 8) {
            if let f = dragFraction, let seconds = axis.seconds(atFraction: f) {
                let lower = controller.timeline?.lowerBound ?? 0
                let lap = axis.lap(atFraction: f).map { "Lap \($0) \u{00B7} " } ?? ""
                Text(lap + MultiviewClock.text(seconds - lower))
                    .font(.footnote)
                    .bold()
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            } else if let number = selected, deck.rows.contains(where: { $0.number == number }) || !deck.race {
                let tla = deck.drivers[number]?.tla ?? number
                Text(tla)
                    .font(.footnote)
                    .bold()
                    .foregroundStyle(Theme.teamColour(deck.drivers[number]?.colour ?? ""))
                Button("Open onboard") { onCar(number) }
                    .font(.footnote)
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                    .controlSize(.small)
                    .accessibilityHint("Shows \(tla)'s onboard")
            } else {
                Text(deck.race ? "Drag to move every feed \u{00B7} tap a marker or a line" : "Drag to move every feed \u{00B7} tap a marker")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Legend()
        }
    }

    /// A tap: on the strip, the nearer of a marker and a radio tick (5 s before it); on the chart,
    /// a line (highlighted), or nothing (the highlight goes).
    private func tapped(at point: CGPoint, deck: DeckState, axis: DeckAxis, markers: [DeckMarker], radio: [RadioTick],
                        width: CGFloat, strip: CGFloat, chart: CGSize) {
        if point.y <= strip {
            let x = Double(point.x), w = Double(width)
            let marker = DeckHitTest.marker(atX: x, in: markers, width: w)
            if let tick = RadioModels.tick(atX: x, in: radio, width: w),
               marker.map({ tick.distance < abs($0.f * w - x) }) ?? true {
                controller.seek(toSeconds: deck.markerTarget(tick.tick.utc, timeline: controller.timeline))
            } else if let marker {
                controller.seek(toSeconds: deck.markerTarget(marker.event.t, timeline: controller.timeline))
            }
            return
        }
        guard deck.race else { return }
        let local = (x: Double(point.x), y: Double(point.y - strip - 4))
        selected = DeckHitTest.line(at: local, rows: deck.rows, axis: axis,
                                    size: (width: Double(chart.width), height: Double(chart.height)))
    }

    static func stripHeight(_ deck: DeckState) -> CGFloat {
        deck.race ? raceStripHeight : timeStripHeight
    }

    static func fraction(_ x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(max(Double(x / width), 0), 1)
    }

    static func spoken(_ markers: [DeckMarker]) -> String {
        let count = markers.count
        return count == 1 ? "1 event so far" : "\(count) events so far"
    }
}

/// The strip's key: SC, red flag, pit, fastest lap.
private struct Legend: View {
    var body: some View {
        HStack(spacing: 8) {
            key(Theme.flagYellow, "SC")
            key(Theme.flagRed, "Red")
            key(Theme.textSecondary, "Pit")
            key(Theme.timingPurple, "Fastest")
            key(Theme.radio, "Radio")
        }
        .font(.caption2)
        .foregroundStyle(Theme.textSecondary)
        .accessibilityHidden(true)
    }

    private func key(_ colour: Color, _ text: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(colour).frame(width: 6, height: 6)
            Text(text)
        }
    }
}

/// Draws the deck: the strip, the lap chart, the fog, the picture-time line and the drag cursor.
/// Plain values in, no actor (as `MapDrawing`).
enum DeckDrawing {
    static func draw(in graphics: inout GraphicsContext, size: CGSize, deck: DeckState, axis: DeckAxis,
                     markers: [DeckMarker], stripHeight: CGFloat, chartHeight: CGFloat, selected: String?,
                     drag: Double?, textScale: CGFloat = 1, radio: [RadioTick] = []) {
        let width = size.width
        guard width > 0 else { return }
        func x(_ f: Double) -> CGFloat { CGFloat(f) * width }

        // The strip's baseline.
        var base = Path()
        base.move(to: CGPoint(x: 0, y: stripHeight / 2))
        base.addLine(to: CGPoint(x: width, y: stripHeight / 2))
        graphics.stroke(base, with: .color(Theme.hairline), lineWidth: 1)

        // Lap lines every 10 laps, labelled under the chart; none across the fog.
        if let total = axis.totalLaps, deck.race {
            for lap in stride(from: 10, to: total + 1, by: 10) {
                guard let f = axis.fraction(ofLap: lap), f <= (axis.fogFrom ?? 1) else { continue }
                var grid = Path()
                grid.move(to: CGPoint(x: x(f), y: stripHeight + 4))
                grid.addLine(to: CGPoint(x: x(f), y: stripHeight + 4 + chartHeight))
                graphics.stroke(grid, with: .color(Theme.hairline), lineWidth: 1)
                graphics.draw(Text("\(lap)").font(.caption2).foregroundStyle(Theme.textTertiary),
                              at: CGPoint(x: x(f), y: stripHeight + 4 + chartHeight + 7))
            }
        }

        drawMarkers(in: &graphics, markers: markers, deck: deck, stripHeight: stripHeight, x: x, textScale: textScale)
        // Team radio: hanging from the strip's top, taller for your driver; under the fog.
        for tick in radio {
            var mark = Path()
            mark.move(to: CGPoint(x: x(tick.f), y: 1))
            mark.addLine(to: CGPoint(x: x(tick.f), y: tick.mine ? stripHeight / 2 - 1 : 7))
            graphics.stroke(mark, with: .color(Theme.radio), lineWidth: tick.mine ? 2 : 1.2)
        }
        if deck.race {
            drawChart(in: &graphics, deck: deck, axis: axis, top: stripHeight + 4,
                      size: CGSize(width: width, height: chartHeight), selected: selected)
        }

        // The fog: an empty, hatched stretch from picture time on.
        if let fog = axis.fogFrom, fog < 1 {
            let rect = CGRect(x: x(fog), y: 0, width: width - x(fog), height: size.height)
            graphics.fill(Path(rect), with: .color(Theme.background.opacity(0.55)))
            var hatch = Path()
            var hx = rect.minX - size.height
            while hx < rect.maxX {
                hatch.move(to: CGPoint(x: hx, y: size.height))
                hatch.addLine(to: CGPoint(x: hx + size.height, y: 0))
                hx += 10
            }
            var clipped = graphics
            clipped.clip(to: Path(rect))
            clipped.stroke(hatch, with: .color(Theme.hairline.opacity(0.6)), lineWidth: 1)
        }

        // Picture time (the whole race shows it inside the drawn race).
        if let now = axis.fraction(ofSeconds: deck.seconds(of: deck.pictureTime)) {
            var line = Path()
            line.move(to: CGPoint(x: x(now), y: 0))
            line.addLine(to: CGPoint(x: x(now), y: size.height))
            graphics.stroke(line, with: .color(Theme.textPrimary), lineWidth: 1.5)
        }

        if let drag {
            var cursor = Path()
            cursor.move(to: CGPoint(x: x(drag), y: 0))
            cursor.addLine(to: CGPoint(x: x(drag), y: size.height))
            graphics.stroke(cursor, with: .color(Theme.accent), lineWidth: 2)
        }
    }

    private static func drawMarkers(in graphics: inout GraphicsContext, markers: [DeckMarker], deck: DeckState,
                                    stripHeight: CGFloat, x: (Double) -> CGFloat, textScale: CGFloat = 1) {
        let mid = stripHeight / 2
        // Bands under the points.
        for marker in markers where marker.isBand {
            let start = x(marker.f), end = x(marker.endF ?? marker.f)
            let colour = marker.event.kind == .red ? Theme.flagRed : Theme.flagYellow
            let rect = CGRect(x: start, y: mid - 5, width: max(end - start, 2), height: 10)
            graphics.fill(Path(roundedRect: rect, cornerRadius: 2),
                          with: .color(marker.event.kind == .vsc ? colour.opacity(0.55) : colour))
        }
        for marker in markers where !marker.isBand {
            let p = CGPoint(x: x(marker.f), y: mid)
            switch marker.event.kind {
            case .lightsOut:
                var tick = Path()
                tick.move(to: CGPoint(x: p.x, y: 2))
                tick.addLine(to: CGPoint(x: p.x, y: stripHeight - 2))
                graphics.stroke(tick, with: .color(Color.white), lineWidth: 2)
            case .chequered:
                for row in 0..<3 {
                    for column in 0..<3 where (row + column) % 2 == 0 {
                        let cell = CGRect(x: p.x - 4.5 + CGFloat(column) * 3, y: p.y - 4.5 + CGFloat(row) * 3, width: 3, height: 3)
                        graphics.fill(Path(cell), with: .color(Color.white))
                    }
                }
                graphics.stroke(Path(CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)),
                                with: .color(Color.white), lineWidth: 0.5)
            case .pit(let car):
                let mine = car == deck.favourite
                var tick = Path()
                tick.move(to: CGPoint(x: p.x, y: mine ? 2 : mid + 2))
                tick.addLine(to: CGPoint(x: p.x, y: stripHeight - 2))
                let colour = mine ? Theme.teamColour(deck.drivers[car]?.colour ?? "") : Theme.textSecondary
                graphics.stroke(tick, with: .color(colour), lineWidth: mine ? 3 : 1)
                if mine {
                    graphics.draw(Text("PIT").font(.system(size: min(8 * textScale, 12), weight: .heavy)).foregroundStyle(colour),
                                  at: CGPoint(x: p.x + 3, y: 6), anchor: .leading)
                }
            case .fastestLap:
                graphics.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)),
                              with: .color(Theme.timingPurple))
            case .retirement(let car):
                var cross = Path()
                cross.move(to: CGPoint(x: p.x - 3.5, y: p.y - 3.5))
                cross.addLine(to: CGPoint(x: p.x + 3.5, y: p.y + 3.5))
                cross.move(to: CGPoint(x: p.x + 3.5, y: p.y - 3.5))
                cross.addLine(to: CGPoint(x: p.x - 3.5, y: p.y + 3.5))
                graphics.stroke(cross, with: .color(car == deck.favourite ? Theme.flagRed : Theme.textSecondary), lineWidth: 1.5)
            case .safetyCar, .vsc, .red:
                break
            }
        }
    }

    private static func drawChart(in graphics: inout GraphicsContext, deck: DeckState, axis: DeckAxis, top: CGFloat,
                                  size: CGSize, selected: String?) {
        guard size.width > 0, size.height > 0 else { return }
        let places = max(deck.rows.count, 2)
        let box = (width: Double(size.width), height: Double(size.height))
        func line(_ row: LapChartRow) -> Path {
            var path = Path()
            var started = false
            for (index, position) in row.positions.enumerated() {
                guard let position, let f = axis.fraction(ofLap: index + 1) else {
                    started = false
                    continue
                }
                let p = CGPoint(x: CGFloat(f) * size.width,
                                y: top + CGFloat(LapChartGeometry.y(position: position, places: places, height: box.height)))
                if started { path.addLine(to: p) } else { path.move(to: p) }
                started = true
            }
            return path
        }
        let style = StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
        // Everyone faintly, then your driver and the tapped line on top.
        for row in deck.rows where row.number != deck.favourite && row.number != selected {
            graphics.stroke(line(row), with: .color(Theme.teamColour(deck.drivers[row.number]?.colour ?? "").opacity(0.45)),
                            style: style)
        }
        for number in [deck.favourite, selected].compactMap({ $0 }) {
            guard let row = deck.rows.first(where: { $0.number == number }) else { continue }
            let colour = number == selected ? Color.white : Theme.teamColour(deck.drivers[number]?.colour ?? "")
            graphics.stroke(line(row), with: .color(colour),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            if let last = LapChartGeometry.points(row, axis: axis, size: box, places: places).last {
                graphics.draw(Text(deck.drivers[number]?.tla ?? number).font(.caption2).bold().foregroundStyle(colour),
                              at: CGPoint(x: CGFloat(last.x) + 4, y: top + CGFloat(last.y)), anchor: .leading)
            }
        }
    }
}

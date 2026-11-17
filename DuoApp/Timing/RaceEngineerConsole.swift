import LiveTiming
import SwiftUI

/// Race Engineer's console, on the laptop's bottom screen under the top onboard (spec sketch):
/// ```
/// ┌──────────────── console ──────────────────┐
/// │ 287 km/h  7th   ▮▮▮▮▮▯ throttle   DRS ●   │
/// │ ▯▯▯▯▯▯ brake    ▬▬▬▬▬▬▬ mini map (HAM ●)  │
/// │ P4  ▲ NOR +1.2s closing  ▼ RUS -0.8s ↗    │
/// │ Medium · 18 laps   Pit now → P7 behind ALO│
/// │ L41 1:32.4 ■■■  L40 1:32.9 ■■□  L39 …     │
/// │ [ Saved for beta.4: team radio ]          │
/// └───────────────────────────────────────────┘
/// ```
/// - The readouts (speed, gear, revs, throttle and brake bars, and the DRS or Aero light only when
///   channel 45 means something) hold their last value and grey after 5 s; a channel F1 leaves out
///   shows "—", never 0.
/// - The race lines: position, the car ahead and behind with the gap and its trend (tap either to
///   make it the top onboard), the tyre, the pit line, and the last 5 laps with sector colours.
/// - A mini map with only this car highlighted (tap a car there too).
/// - The drawn and labelled "Saved for beta.4: team radio" spot.
///
/// Everything comes from `TimingController.console`, built at the 2 Hz tick; only the leaf views
/// read it. With no onboard on top it says "Tap a car to pick an onboard", and the mini map shows
/// every car to tap.
struct RaceEngineerConsole: View {
    let timing: TimingController
    /// A car tapped (ahead, behind, or on the mini map), by racing number: it becomes the top
    /// onboard.
    let onCar: @MainActor (String) -> Void

    var body: some View {
        DataRegionFrame {
            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 10) {
                    ConsoleLines(timing: timing, onCar: onCar)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    VStack(spacing: 8) {
                        ConsoleMiniMap(timing: timing, onCar: onCar)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        DataRegionPlaceholder(caption: ConsoleText.radio, inset: 6)
                            .frame(height: 48)
                    }
                    .frame(width: max(proxy.size.width * 0.38, 0))
                }
                .padding(10)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Race Engineer")
    }
}

/// The mini map: this car in full, the others as grey dots. Its own view, so only it follows the
/// top car.
private struct ConsoleMiniMap: View {
    let timing: TimingController
    let onCar: @MainActor (String) -> Void

    var body: some View {
        MapPanel(timing: timing, onCar: onCar, highlight: timing.console?.number)
    }
}

/// The readouts and race lines, or the hint when no onboard is on top.
private struct ConsoleLines: View {
    let timing: TimingController
    let onCar: @MainActor (String) -> Void

    var body: some View {
        if let console = timing.console {
            VStack(alignment: .leading, spacing: 6) {
                ConsoleHeader(console: console)
                ConsoleReadouts(console: console)
                if console.race {
                    ConsoleRivals(console: console, onCar: onCar)
                }
                ConsoleTyreAndPit(console: console)
                ConsoleLaps(laps: console.laps)
                Spacer(minLength: 0)
            }
        } else {
            Text(ConsoleText.pickOnboard)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// "HAM  Hamilton                P4".
private struct ConsoleHeader: View {
    let console: ConsoleState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(console.tla)
                .font(.headline)
                .fontWidth(.condensed)
                .foregroundStyle(Theme.teamColour(console.teamColour))
            Text(console.lastName)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(ConsoleText.position(console.position))
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Speed, gear, revs, the light, and the throttle and brake bars.
private struct ConsoleReadouts: View {
    let console: ConsoleState

    var body: some View {
        let readout = console.readout
        let stale = readout?.stale ?? false
        let ink = stale ? Theme.textTertiary : Theme.textPrimary
        let metric = TimingText.usesKilometres(Locale.current.measurementSystem)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(ConsoleText.speed(readout?.speedKmh, metric: metric))
                    .font(.title3)
                    .bold()
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .fixedSize()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(ConsoleText.gear(readout?.gear))
                        .font(.title3)
                        .bold()
                        .monospacedDigit()
                        .foregroundStyle(ink)
                    Text("gear")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                .fixedSize()
                Text(ConsoleText.rpm(readout?.rpm))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(stale ? Theme.textTertiary : Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let light = console.light {
                    ConsoleLight(label: light, lit: readout?.aero == true && !stale)
                }
            }
            ConsoleBar(title: "Throttle", fill: ConsoleText.fill(readout?.throttle), colour: Theme.timingGreen, stale: stale)
            ConsoleBar(title: "Brake", fill: ConsoleText.fill(readout?.brake), colour: Theme.flagRed, stale: stale)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The DRS or Aero light: filled green while open or engaged.
private struct ConsoleLight: View {
    let label: String
    let lit: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .bold()
                .foregroundStyle(lit ? Theme.textPrimary : Theme.textSecondary)
            Circle()
                .fill(lit ? Theme.timingGreen : Color.clear)
                .overlay { Circle().strokeBorder(lit ? Theme.timingGreen : Theme.textTertiary, lineWidth: 1.5) }
                .frame(width: 11, height: 11)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lit ? "\(label) open" : "\(label) closed")
    }
}

/// A pedal bar, 0–100 %; empty when the channel is absent.
private struct ConsoleBar: View {
    let title: String
    let fill: Double?
    let colour: Color
    let stale: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 52, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.raised)
                    if let fill {
                        Capsule()
                            .fill(stale ? Theme.textTertiary : colour)
                            .frame(width: max(proxy.size.width * fill, 0))
                    }
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(fill.map { "\(Int(($0 * 100).rounded())) percent" } ?? "No data")
    }
}

/// The cars ahead and behind; tapping one makes it the top onboard.
private struct ConsoleRivals: View {
    let console: ConsoleState
    let onCar: @MainActor (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let ahead = console.ahead {
                ConsoleRivalRow(symbol: "arrowtriangle.up.fill", word: "Ahead", rival: ahead, onCar: onCar)
            }
            if let behind = console.behind {
                ConsoleRivalRow(symbol: "arrowtriangle.down.fill", word: "Behind", rival: behind, onCar: onCar)
            }
        }
    }
}

private struct ConsoleRivalRow: View {
    let symbol: String
    let word: String
    let rival: ConsoleRival
    let onCar: @MainActor (String) -> Void

    var body: some View {
        Button {
            if let number = rival.number { onCar(number) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                Text(rival.tla)
                    .font(.footnote)
                    .bold()
                    .foregroundStyle(Theme.textPrimary)
                Text(rival.gap)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(ConsoleText.trend(rival.closing))
                    .font(.caption)
                    .foregroundStyle(rival.closing == true ? Theme.flagYellow : Theme.textSecondary)
                Spacer(minLength: 0)
                Image(systemName: "video")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(rival.number == nil)
        .accessibilityLabel("\(word): \(rival.tla) \(rival.gap) \(ConsoleText.trend(rival.closing))")
        .accessibilityHint("Shows \(rival.tla)'s onboard")
    }
}

/// "Medium · 18 laps   Pit now → P7 behind ALO".
private struct ConsoleTyreAndPit: View {
    let console: ConsoleState

    var body: some View {
        if console.tyre != nil || console.pitLine != nil {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let tyre = console.tyre {
                    Text(tyre)
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                }
                if let pit = console.pitLine {
                    Text(pit)
                        .font(.footnote)
                        .foregroundStyle(pit.hasPrefix("Pit now") ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// The last 5 laps, newest first: "L41 1:32.456 ■■■".
private struct ConsoleLaps: View {
    let laps: [ConsoleLap]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(laps) { lap in
                HStack(spacing: 8) {
                    Text("L\(lap.lap)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 34, alignment: .leading)
                    Text(lap.time.isEmpty ? ConsoleText.absent : lap.time)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 68, alignment: .leading)
                    HStack(spacing: 2) {
                        ForEach(Array(lap.sectors.enumerated()), id: \.offset) { entry in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(TimingColours.sector(entry.element))
                                .frame(width: 14, height: 7)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Lap \(lap.lap), \(lap.time.isEmpty ? "no time" : lap.time)")
            }
        }
    }
}

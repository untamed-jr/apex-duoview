import LiveTiming
import SwiftUI

/// Onboard and Logbook's right screen (`DataRegions.logbook`): the logbook of the onboard on the
/// left screen (the main feed, which the controller picks by Race Engineer's rules), in one
/// column:
/// ```
/// ┌──────────── logbook ────────────┐
/// │ ▌HAM   P4   Medium · 18 laps    │
/// │        Last lap 1:32.456        │
/// │  ▲ NOR            ▼ RUS         │
/// │ RADIO  (clips, transcripts, ▶)  │
/// │ LAPS   L41 1:32.456 ■■■ …       │
/// │ STOPS  Lap 23 · 21.8 s · M → H  │
/// │ RACE CONTROL  Lap 30 · CAR 44…  │
/// └─────────────────────────────────┘
/// ```
/// - Everything is read at the cut (picture time; the whole race with "Show the whole race" on);
///   with no picture time nothing shows but the header's code. The logbook is built off the main
///   actor twice a second (`BookModels.logbook`); a build for another car, or for later than the
///   picture now (a rewind meanwhile), is dropped. The one showing keeps the moment it was built
///   for, and hides (back to the code alone) as soon as the picture is earlier than that, checked
///   four times a second (`BookModels.logbookShows`), so a rewind never leaves stops or race
///   control from after the picture on screen until the next build lands.
/// - Radio comes from the radio's rows (`clips(for:limit:)`), so only clips the picture has
///   reached, with their transcripts through the gated queue; this view counts as a radio view
///   (`setSurface`), so transcription runs while it shows. A row's tap plays it, or stops it.
/// - Tapping the car ahead or behind switches both screens: its onboard comes up on the left by
///   the tap-a-car rules (`onCar`, Race Engineer's `showOnboardOnTop`), and the logbook follows.
struct LogbookView: View {
    let controller: MultiviewController
    let timing: TimingController
    let radio: RadioController
    let onCar: @MainActor (String) -> Void

    @State private var model: LogbookModel?
    /// The cut `model` was built at (nil: the whole race).
    @State private var modelCut: UTCms?

    var body: some View {
        let car = controller.topOnboardNumber
        DataRegionFrame {
            Group {
                if let car, let session = timing.loadedSession {
                    // Re-checked 4 times a second against picture time (not observed), so a rewind
                    // hides a build from later than the picture at once.
                    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                        content(car: car, session: session, model: shownModel)
                    }
                } else {
                    Text(timing.timingHidden ? (timing.catchUpNote ?? "") : BookModels.pickOnboard)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { radio.setSurface(BookModels.logbookSurface, shown: true) }
        .onDisappear { radio.setSurface(BookModels.logbookSurface, shown: false) }
        // A new car: its logbook from nothing (never the last car's), then twice a second.
        .task(id: car) {
            model = nil
            modelCut = nil
            guard let car else { return }
            while !Task.isCancelled {
                await refresh(car: car)
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Logbook")
    }

    /// One build at the cut, off the main actor; kept only if it is still for this car and not
    /// ahead of the picture.
    private func refresh(car: String) async {
        guard let session = timing.loadedSession, !timing.timingHidden else {
            if model != nil { model = nil }
            return
        }
        let t = timing.pictureTime, whole = timing.showWholeRace
        // The one showing is from later than the picture (a rewind): gone now, not after this build.
        if model != nil, !BookModels.logbookShows(cut: modelCut, pictureTime: t, wholeRace: whole) { model = nil }
        let built = await Task.detached(priority: .userInitiated) {
            BookModels.logbook(car: car, pictureTime: t, wholeRace: whole, session: session)
        }.value
        guard !Task.isCancelled, controller.topOnboardNumber == car else { return }
        // A rewind landed while it was built: wait for the next build at the new moment.
        if !timing.showWholeRace {
            guard let t, let now = timing.pictureTime, t <= now else {
                if model != nil { model = nil }
                return
            }
        }
        if model != built { model = built }
        modelCut = whole ? nil : t
    }

    /// The build, only while it isn't from later than the picture.
    private var shownModel: LogbookModel? {
        guard let model,
              BookModels.logbookShows(cut: modelCut, pictureTime: timing.pictureTime, wholeRace: timing.showWholeRace)
        else { return nil }
        return model
    }

    private func content(car: String, session: LoadedSession, model: LogbookModel?) -> some View {
        let code = CompanionModels.code(car, drivers: session.drivers)
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                if let note = timing.catchUpNote {
                    TimingQuietLine(text: note)
                }
                if let model {
                    LogbookHeader(header: BookModels.header(model, drivers: session.drivers), onCar: onCar)
                } else {
                    LogbookCode(code: code, teamColour: session.drivers[car]?.teamColour ?? "")
                }
                LogbookRadio(radio: radio, car: car, code: code)
                if let model {
                    LogbookLaps(rows: BookModels.lapRows(model.laps))
                    LogbookStops(stops: model.stops)
                    LogbookRaceControl(rows: BookModels.raceControlRows(model.raceControl, car: car, session: session),
                                       code: code)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

/// A section's title: "RADIO", "LAPS", "STOPS", "RACE CONTROL".
private struct LogbookSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .sectionLabel()
            .accessibilityAddTraits(.isHeader)
    }
}

/// The empty line of a section.
private struct LogbookEmptyLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The team-colour bar and code, alone (before the first build lands).
private struct LogbookCode: View {
    let code: String
    let teamColour: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Theme.teamColour(teamColour))
                .frame(width: 4, height: 26)
            Text(code)
                .font(.title2)
                .bold()
                .fontWidth(.condensed)
                .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "▌HAM  P4  Medium · 18 laps", the last lap, and the cars ahead and behind (a tap switches both
/// screens to that car).
private struct LogbookHeader: View {
    let header: BookModels.Header
    let onCar: @MainActor (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                LogbookCode(code: header.code, teamColour: header.teamColour)
                Text(header.position)
                    .font(.title2)
                    .bold()
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if let tyre = header.tyre {
                    Text(tyre)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            if let last = header.lastLap {
                HStack(spacing: 6) {
                    Text("Last lap")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(last)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                }
                .accessibilityElement(children: .combine)
            }
            if header.ahead != nil || header.behind != nil {
                HStack(spacing: 8) {
                    if let ahead = header.ahead {
                        neighbour(symbol: "arrowtriangle.up.fill", word: "Ahead", car: ahead)
                    }
                    if let behind = header.behind {
                        neighbour(symbol: "arrowtriangle.down.fill", word: "Behind", car: behind)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func neighbour(symbol: String, word: String, car: (number: String, code: String)) -> some View {
        Button {
            onCar(car.number)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                Text(car.code)
                    .font(.footnote)
                    .bold()
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "video")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 34)
            .contentShape(Capsule())
        }
        .buttonStyle(.glass)
        .accessibilityLabel("\(word): \(car.code)")
        .accessibilityHint("Shows \(car.code)'s onboard and logbook")
    }
}

/// The car's clips at the cut, oldest first, with lap headers and transcripts; a tap plays or stops.
/// It reads only the radio's rows, so the logbook's 2 Hz build doesn't redraw it.
private struct LogbookRadio: View {
    let radio: RadioController
    let car: String
    let code: String

    var body: some View {
        let rows = radio.clips(for: car, limit: nil)
        VStack(alignment: .leading, spacing: 4) {
            LogbookSectionTitle(title: BookModels.radioTitle)
            if rows.isEmpty {
                LogbookEmptyLine(text: BookModels.noRadio(code))
            } else {
                ForEach(rows) { row in
                    if let header = row.header {
                        Text(header)
                            .font(.caption2)
                            .bold()
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 2)
                            .accessibilityAddTraits(.isHeader)
                    }
                    RadioRow(row: row, playing: radio.playing == row.path) {
                        if radio.playing == row.path {
                            radio.stop()
                        } else {
                            radio.play(path: row.path)
                        }
                    }
                }
            }
            if let notice = radio.notice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(Theme.flagYellow)
            }
            if let note = radio.transcriptNote {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// The laps, newest first: "L41 1:32.456 ■■■" with the lap's own colour and its sector colours.
private struct LogbookLaps: View {
    let rows: [BookModels.LapRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            LogbookSectionTitle(title: BookModels.lapsTitle)
            if rows.isEmpty {
                LogbookEmptyLine(text: ConsoleText.absent)
            } else {
                ForEach(rows) { lap in
                    HStack(spacing: 8) {
                        Text("L\(lap.lap)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 38, alignment: .leading)
                        Text(lap.time)
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(TimingColours.lap(lap.pace))
                            .frame(width: 76, alignment: .leading)
                        HStack(spacing: 2) {
                            ForEach(Array(lap.sectors.enumerated()), id: \.offset) { entry in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(TimingColours.sector(entry.element))
                                    .frame(width: 16, height: 7)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Lap \(lap.lap), \(lap.time == ConsoleText.absent ? "no time" : lap.time)")
                }
            }
        }
    }
}

/// "Lap 23 · 21.8 s · Medium → Hard", one per stop, or "No stops yet."
private struct LogbookStops: View {
    let stops: [LogbookStop]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            LogbookSectionTitle(title: BookModels.stopsTitle)
            if stops.isEmpty {
                LogbookEmptyLine(text: BookModels.noStops)
            } else {
                ForEach(Array(stops.enumerated()), id: \.offset) { entry in
                    Text(BookModels.stopLine(entry.element))
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(entry.element.laneMs == nil ? Theme.textPrimary : Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The messages naming the car (penalties, investigations, track limits), oldest first, each with
/// its lap; blue flags left out. "Nothing from race control about {CODE}." when there are none.
private struct LogbookRaceControl: View {
    let rows: [BookModels.RaceControlRow]
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            LogbookSectionTitle(title: BookModels.raceControlTitle)
            if rows.isEmpty {
                LogbookEmptyLine(text: BookModels.noRaceControl(code))
            } else {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 1) {
                        if let label = row.label {
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Text(row.text)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

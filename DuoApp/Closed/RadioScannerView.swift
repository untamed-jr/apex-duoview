import LiveTiming
import Multiview
import SwiftUI

/// The closed phone's Radio Scanner: one driver's radio. On top the code, team colour, position
/// and lap; then their clips so far, each one's transcript in large type, the newest at the bottom
/// (older ones scroll off the top as new ones come); one big ▶ / ■.
///
/// - The clips come from the radio's rows (`clips(for:limit:)`), so only clips the picture has
///   reached, with transcripts through the gated queue. This page counts as a radio view, so
///   transcription runs while it shows (`setSurface`).
/// - It listens to its driver (`radio.listen`). A clip that normal play crosses (`radio.crossed`,
///   never rows appearing, a seek or a scrub) plays by itself with "Play radio as it happens" on;
///   with it off, "New radio — tap to play".
/// - Left and right change the driver in race order (never "drivers with radio"); the choice is
///   remembered. The default is your driver, else the leader; a remembered driver this session
///   lacks is passed over. Up and down are the pager's.
/// - Sizes come from the page's own size; the type scales with its height.
struct RadioScannerView: View {
    static let surface = "closed.scanner"

    let radio: RadioController
    let timing: TimingController
    let settings: CompanionSettings
    let size: CGSize
    let onPageSwipe: @MainActor (CompanionModels.Swipe) -> Void
    let onBackground: @MainActor () -> Void

    /// The driver chosen by a swipe (or remembered); read from Settings once.
    @State private var chosen: String?
    @State private var loadedChoice = false
    /// A clip crossed with auto-play off, waiting for a tap.
    @State private var pending: String?
    /// With no driver chosen and none of yours: the leader when the page first found one, kept
    /// (not remembered) so a change of lead doesn't move the page to another driver.
    @State private var heldLeader: String?

    var body: some View {
        Group {
            if let session = timing.loadedSession {
                scanner(session)
            } else {
                VStack(spacing: 12) {
                    title
                    LaptopTimingNote(timing: timing)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { onBackground() }
        .gesture(DragGesture(minimumDistance: 24).onEnded { value in swiped(value.translation) })
        .onAppear {
            if !loadedChoice {
                chosen = settings.scannerDriver
                loadedChoice = true
            }
            radio.setSurface(Self.surface, shown: true)
        }
        .onDisappear {
            radio.listen([])
            radio.setSurface(Self.surface, shown: false)
        }
        .onChange(of: order.first, initial: true) { _, first in
            if heldLeader == nil { heldLeader = first }
        }
        // One stream per driver: auto-play (or the prompt) only from clips crossed in normal play.
        .task(id: driverNow) {
            pending = nil
            radio.listen(driverNow.map { [$0] } ?? [])
            guard driverNow != nil else { return }
            for await clip in radio.crossed {
                if settings.autoPlayRadio {
                    radio.play(path: clip.path)
                } else {
                    pending = clip.path
                }
            }
        }
    }

    private var title: some View {
        Text(CompanionModels.scannerTitle)
            .font(.system(size: max(13, size.height * 0.022), weight: .semibold))
            .fontWidth(.condensed)
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textSecondary)
    }

    /// The race order now: by timing position, every car the session names.
    private var order: [String] {
        guard let session = timing.loadedSession else { return [] }
        return ClosedPager.raceOrder(at: timing.pictureTime ?? .min, session: session)
    }

    private var driverNow: String? {
        CompanionModels.scannerDriver(stored: chosen, favourite: radio.favourite, held: heldLeader, order: order)
    }

    private func scanner(_ session: LoadedSession) -> some View {
        let number = driverNow
        // Re-read with the rows (observed, 2 Hz): only clips the picture has reached.
        let rows = number.map { radio.clips(for: $0, limit: nil) } ?? []
        let playingHere = radio.playing.map { path in rows.contains { $0.path == path } } ?? false
        let waiting = pending.flatMap { path in rows.contains { $0.path == path } ? path : nil }
        let h = size.height
        return VStack(spacing: h * 0.02) {
            title
                .padding(.top, h * 0.06)
            if let number {
                // Position and lap move with the picture: twice a second.
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    header(CompanionModels.scannerHeader(number: number, at: timing.pictureTime, session: session))
                }
                transcripts(rows, code: CompanionModels.code(number, drivers: session.drivers))
                if let waiting {
                    Button {
                        pending = nil
                        radio.play(path: waiting)
                    } label: {
                        Text(CompanionModels.newRadio)
                            .font(.system(size: max(15, h * 0.026), weight: .semibold))
                            .padding(.horizontal, 6)
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(.glass)
                }
                playButton(rows: rows, playingHere: playingHere, waiting: waiting)
                    .padding(.bottom, h * 0.05)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, max(16, size.width * 0.05))
    }

    private func header(_ h: CompanionModels.ScannerHeader) -> some View {
        let big = max(28, size.height * 0.07)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Theme.teamColour(h.teamColour))
                .frame(width: 6, height: big * 0.9)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - big * 0.12 }
            Text(h.code)
                .font(.system(size: big, weight: .heavy))
                .fontWidth(.condensed)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                if let position = h.position {
                    Text(position)
                        .font(.system(size: big * 0.6, weight: .bold))
                        .fontWidth(.condensed)
                        .foregroundStyle(Theme.textPrimary)
                }
                if let lap = h.lap {
                    Text(lap)
                        .font(.system(size: max(13, size.height * 0.024)))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The clips' words, newest at the bottom; older ones go off the top (no scrolling by hand:
    /// up and down change the page). The lap header whenever it changes, as the Radio panel.
    @ViewBuilder
    private func transcripts(_ rows: [RadioRowModel], code: String) -> some View {
        let h = size.height
        if rows.isEmpty {
            Text(CompanionModels.noRadio(code))
                .font(.system(size: max(17, h * 0.032)))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: h * 0.018) {
                Spacer(minLength: 0)
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        if let header = row.header {
                            Text(header)
                                .font(.system(size: max(12, h * 0.02), weight: .semibold))
                                .fontWidth(.condensed)
                                .textCase(.uppercase)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Text(words(row))
                            .font(.system(size: max(20, h * 0.042), weight: .semibold))
                            .foregroundStyle(radio.playing == row.path ? Theme.textPrimary : Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(row.isNew ? 0.12 : 0))
                    }
                    .animation(.easeInOut(duration: 0.6), value: row.isNew)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Radio from \(row.tla)\(row.label.map { ", \($0)" } ?? ""). \(words(row))")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .clipped()
            .animation(.snappy, value: rows.map(\.path))
        }
    }

    /// The words, or "Transcribing…" / "(no words recognised)"; the lap label when there are none
    /// yet (Transcripts off, or not reached).
    private func words(_ row: RadioRowModel) -> String {
        TranscriptState.rowText(row.transcript) ?? row.label ?? row.tla
    }

    /// ■ while one of this driver's clips plays; ▶ plays the one waiting, else the newest.
    private func playButton(rows: [RadioRowModel], playingHere: Bool, waiting: String?) -> some View {
        let side = max(64, size.height * 0.13)
        let target = waiting ?? rows.last?.path
        return Button {
            if playingHere {
                radio.stop()
            } else if let target {
                pending = nil
                radio.play(path: target)
            }
        } label: {
            Image(systemName: playingHere ? "stop.fill" : "play.fill")
                .font(.system(size: side * 0.4, weight: .bold))
                .frame(width: side, height: side)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(playingHere ? Theme.accent : Theme.raised)
        .disabled(!playingHere && target == nil)
        .accessibilityLabel(playingHere ? "Stop the clip" : "Play the newest clip")
    }

    private func swiped(_ translation: CGSize) {
        guard let swipe = CompanionModels.swipe(translation, distance: 50) else { return }
        switch swipe {
        case .up, .down:
            onPageSwipe(swipe)
        case .left, .right:
            // Left is the next driver in race order, as Picture's left is the next feed.
            guard let next = ClosedPager.driver(after: driverNow, forward: swipe == .left, order: order) else { return }
            chosen = next
            settings.scannerDriver = next
        }
    }
}

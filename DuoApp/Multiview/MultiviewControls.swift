import F1TV
import LiveTiming
import Multiview
import SwiftUI

/// The multiview's own controls, in the beta.1 style (dark translucent capsules, condensed
/// headings, red only for progress and LIVE), laid inside the safe area by `MultiviewView`.
///
/// - Top: Close, the session title, "Switch layout" (only with more than one usable layout), "Map"
///   and "Radio" (only with timing) and "Feeds".
/// - Bottom: one scrubber for every feed with the elapsed and remaining time, play/pause, LIVE for
///   live sessions, the speed (not at the live edge) and the audio language of the feed with the
///   sound (only with more than one option).
///
/// `MultiviewView` decides when they show. Hidden, they stay in place, see-through and untouchable
/// (an open menu isn't torn down when the timer fires), and a small handle at the top edge brings
/// them back. Only the buttons and the bottom panel take touches: the space between them reaches
/// the tiles underneath. A notice ("Caught up to live…") shows whether or not the controls do.
///
/// The time is read only by `MultiviewScrubber` and `MultiviewPlaybackBar`, so the twice-a-second
/// update redraws them alone, never the tiles. Timing is read only by `TimingMapButton` and
/// `TimelineMarksStrip`.
struct MultiviewControls: View {
    let controller: MultiviewController
    let visible: Bool
    let canSwitchLayout: Bool
    /// Extra room on the leading and trailing sides for the bottom panel and the handle, in the
    /// controls' own space: in book posture, everything but the screen half that holds the main
    /// feed, so neither straddles the crease. Zero otherwise.
    let mainHalfLeading: CGFloat
    let mainHalfTrailing: CGFloat
    /// The same for the handle, which is centred over the main tile (inside the main half in
    /// book posture): away from Close, and from every tile's speaker.
    let handleLeading: CGFloat
    let handleTrailing: CGFloat
    /// True while the scrubber is held: the controls stay up.
    @Binding var scrubbing: Bool
    let onShow: @MainActor () -> Void
    /// Any use of the controls restarts the hide timer.
    let onInteraction: @MainActor () -> Void
    let onSwitchLayout: @MainActor () -> Void
    let onFeeds: @MainActor () -> Void
    /// The phone is open flat: the "Try laptop pose" tip may show.
    var isFlat = false

    var body: some View {
        // The error has its own Close, over everything.
        if controller.errorText == nil {
            ZStack {
                VStack(spacing: 0) {
                    MultiviewTopBar(
                        controller: controller,
                        canSwitchLayout: canSwitchLayout,
                        onInteraction: onInteraction,
                        onSwitchLayout: onSwitchLayout,
                        onFeeds: onFeeds,
                        isFlat: isFlat)
                    Spacer(minLength: 0)
                    MultiviewPlaybackBar(controller: controller, scrubbing: $scrubbing, onInteraction: onInteraction)
                        .padding(.leading, mainHalfLeading)
                        .padding(.trailing, mainHalfTrailing)
                }
                .opacity(visible ? 1 : 0)
                .allowsHitTesting(visible)
                .accessibilityHidden(!visible)

                // At the top, centred over the main tile, well clear of Close: a second tap on it,
                // once the controls are up, never lands on Close.
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        MultiviewControlsHandle(onShow: onShow)
                            .appTip(ControlsHiddenTip())
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, handleLeading)
                    .padding(.trailing, handleTrailing)
                    Spacer(minLength: 0)
                }
                .opacity(visible ? 0 : 1)
                .allowsHitTesting(!visible)
                .accessibilityHidden(visible)

                MultiviewNoticeView(controller: controller)
            }
            .animation(.easeOut(duration: 0.2), value: visible)
        }
    }
}

// MARK: - Top bar

/// Close and the title on the leading side; "Switch layout", "Map" and "Feeds" on the trailing side,
/// kept 56 pt in from the edge so the top-right tile's speaker stays reachable while the controls
/// are held up (paused, loading).
struct MultiviewTopBar: View {
    let controller: MultiviewController
    let canSwitchLayout: Bool
    let onInteraction: @MainActor () -> Void
    let onSwitchLayout: @MainActor () -> Void
    let onFeeds: @MainActor () -> Void
    /// The phone is open flat: the "Try laptop pose" tip may show on Switch layout.
    var isFlat = false

    var body: some View {
        // Design pass q1: the bar's pieces are clear glass in one container, so they blend as
        // one group over the video.
        GlassEffectContainer(spacing: 8) {
            bar
        }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            Button {
                controller.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.bold())
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .videoGlass(in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            if !controller.title.isEmpty {
                Text(controller.title)
                    .heading(.subheadline)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .videoGlass(in: Capsule())
                    // Not a control: touches pass to the tile underneath.
                    .allowsHitTesting(false)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            if canSwitchLayout {
                Button {
                    onInteraction()
                    onSwitchLayout()
                } label: {
                    MultiviewChromeLabel(title: "Switch layout", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.plain)
                .fixedSize()
                .appTip(isFlat ? LaptopPoseTip() : nil)
            }
            TimingMapButton(timing: controller.timing, onInteraction: onInteraction)
                .appTip(TapCarTip())
            RadioButton(radio: controller.radio, timing: controller.timing, onInteraction: onInteraction)
            if !controller.channels.isEmpty {
                Button {
                    onInteraction()
                    onFeeds()
                } label: {
                    MultiviewChromeLabel(title: "Feeds", systemImage: "rectangle.grid.2x2")
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, Self.speakerClearance)
        .padding(.top, 8)
    }

    /// The tile speaker's 44 pt hit area, plus room.
    static let speakerClearance: CGFloat = 56
}

/// A control's look: white condensed text on a clear-glass capsule, in a 44 pt high hit area.
struct MultiviewChromeLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.bold())
            .fontWidth(.condensed)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .videoGlass(in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// While the controls are hidden: a small "•••" at the top edge that brings them back.
struct MultiviewControlsHandle: View {
    let onShow: @MainActor () -> Void

    var body: some View {
        Button {
            onShow()
        } label: {
            Image(systemName: "ellipsis")
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .frame(width: 36, height: 22)
                .videoGlass(in: Capsule())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show controls")
    }
}

// MARK: - Bottom panel

/// The scrubber over a row of play/pause, LIVE, speed and audio language.
struct MultiviewPlaybackBar: View {
    let controller: MultiviewController
    @Binding var scrubbing: Bool
    let onInteraction: @MainActor () -> Void

    var body: some View {
        // Nothing to control before the feeds have started, or with no feed at all.
        if controller.slots[0] != nil, !controller.isLoading {
            panel
                .frame(maxWidth: 640)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            if let range = controller.timeline, range.upperBound - range.lowerBound >= 1 {
                MultiviewScrubber(
                    controller: controller, range: range, scrubbing: $scrubbing, onInteraction: onInteraction)
            }
            HStack(spacing: 8) {
                playButton
                if controller.isLive {
                    liveButton
                }
                Spacer(minLength: 8)
                if !controller.isAtLiveEdge {
                    speedMenu
                }
                if controller.audioOptions.count > 1 {
                    audioMenu
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        // Design pass q1: clear glass, as Apple's own player controls.
        .videoGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var playButton: some View {
        let paused = controller.isPaused
        return Button {
            if paused { controller.play() } else { controller.pause() }
            onInteraction()
        } label: {
            Image(systemName: paused ? "play.fill" : "pause.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(paused ? "Play" : "Pause")
    }

    /// Red when at the live point; behind it, an outlined LIVE that returns there.
    private var liveButton: some View {
        let atEdge = controller.isAtLiveEdge
        return Button {
            controller.goLive()
            onInteraction()
        } label: {
            liveLabel(atEdge: atEdge)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(atEdge ? "Live" : "Go live")
    }

    @ViewBuilder
    private func liveLabel(atEdge: Bool) -> some View {
        if atEdge {
            Text("LIVE").liveBadge()
        } else {
            Text("LIVE")
                .font(.caption)
                .bold()
                .fontWidth(.condensed)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay { Capsule().strokeBorder(Theme.accent, lineWidth: 1.5) }
        }
    }

    private var speedMenu: some View {
        let current = controller.rate
        return Menu {
            ForEach(SyncPolicy.speeds, id: \.self) { speed in
                Button {
                    controller.setRate(speed)
                    onInteraction()
                } label: {
                    if speed == current {
                        Label(MultiviewClock.speedText(speed), systemImage: "checkmark")
                    } else {
                        Text(MultiviewClock.speedText(speed))
                    }
                }
            }
        } label: {
            Text(MultiviewClock.speedText(current))
                .font(.footnote.bold())
                .fontWidth(.condensed)
                .monospacedDigit()
                .foregroundStyle(current == 1 ? Theme.textSecondary : Color.white)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        // Opening the menu counts as a use: the 4 s start again (a Menu has no open callback).
        .simultaneousGesture(TapGesture().onEnded { onInteraction() })
        .accessibilityLabel("Speed \(MultiviewClock.speedText(current))")
    }

    /// The feed with the sound's audio choices, under its name.
    private var audioMenu: some View {
        let options: [MultiviewAudioOption] = controller.audioOptions
        let selected: Int? = controller.selectedAudioOption
        let chosenName: String = options.first(where: { $0.id == selected })?.name ?? "Audio"
        let audible: Int? = controller.audioChannelId
        let feed: Channel? = controller.slots.compactMap({ $0 }).first(where: { $0.id == audible })
        let feedTitle: String = feed?.displayTitle ?? ""
        return Menu {
            Section(feedTitle.isEmpty ? "Audio" : "Sound from \(feedTitle)") {
                ForEach(options) { option in
                    Button {
                        controller.selectAudioOption(option.id)
                        onInteraction()
                    } label: {
                        if option.id == selected {
                            Label(option.name, systemImage: "checkmark")
                        } else {
                            Text(option.name)
                        }
                    }
                }
            }
        } label: {
            Label(chosenName, systemImage: "waveform")
                .font(.footnote.bold())
                .fontWidth(.condensed)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: 160)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .simultaneousGesture(TapGesture().onEnded { onInteraction() })
        .accessibilityLabel("Audio language, \(chosenName)")
    }
}

/// One scrubber for every feed, on the main feed's timeline. Dragging previews the time; letting
/// go seeks every feed together, once (no seeking while the finger moves).
struct MultiviewScrubber: View {
    let controller: MultiviewController
    let range: ClosedRange<Double>
    @Binding var scrubbing: Bool
    let onInteraction: @MainActor () -> Void

    /// Where the finger is, while it drags.
    @State private var preview: Double?

    var body: some View {
        let lower = range.lowerBound
        let upper = range.upperBound
        let shown: Double = min(max(preview ?? controller.position, lower), upper)
        HStack(spacing: 8) {
            Text(MultiviewClock.text(shown - lower))
                .font(.caption)
                .fontWidth(.condensed)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .accessibilityHidden(true)
            Slider(
                value: Binding(get: { shown }, set: { preview = $0 }),
                in: range,
                onEditingChanged: { editing in editingChanged(editing) })
                .tint(Theme.accent)
                .accessibilityLabel("Position")
                .accessibilityValue(MultiviewClock.text(shown - lower))
                // Lights out, chequered and flag bands just under the track; no change to layout.
                .overlay(alignment: .bottom) {
                    TimelineMarksStrip(timing: controller.timing, range: range)
                }
            Text(trailingText(shown: shown))
                .font(.caption)
                .fontWidth(.condensed)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .accessibilityHidden(true)
        }
        // Removed mid-drag (the timeline went away, a refresh): the controls aren't held up.
        .onDisappear {
            preview = nil
            scrubbing = false
        }
    }

    /// The time left in a replay; live, how far behind the live point (nothing when at it).
    private func trailingText(shown: Double) -> String {
        let left = max(range.upperBound - shown, 0)
        if controller.isLive, left <= MultiviewController.liveEdgeSlack { return "" }
        return "−" + MultiviewClock.text(left)
    }

    private func editingChanged(_ editing: Bool) {
        if editing {
            scrubbing = true
        } else {
            if let preview { controller.seek(toSeconds: preview) }
            preview = nil
            scrubbing = false
        }
        onInteraction()
    }
}

// MARK: - Timeline marks

/// The timing's marks under the scrubber's track: lights out (a white tick), the chequered flag
/// (a small chequer) and safety car, VSC and red flag periods (yellow or red bars), each at its
/// moment less the timing offset, clipped to what the scrubber spans. Not touchable.
struct TimelineMarksStrip: View {
    let timing: TimingController
    let range: ClosedRange<Double>

    static let height: CGFloat = 6

    var body: some View {
        let marks = timing.timelineMarks.compactMap { $0.clipped(to: range) }
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                ForEach(Array(marks.enumerated()), id: \.offset) { entry in
                    TimelineMarkView(mark: entry.element, range: range, width: width)
                }
            }
        }
        .frame(height: Self.height)
        .padding(.horizontal, TimelineMarkLayout.trackInset)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(marks.isEmpty ? "" : "Timeline marks: " + marks.map(\.label).joined(separator: ", "))
        .accessibilityHidden(marks.isEmpty)
    }
}

/// One mark, placed along the strip.
private struct TimelineMarkView: View {
    let mark: TimelineMark
    let range: ClosedRange<Double>
    let width: CGFloat

    var body: some View {
        switch mark {
        case .band(let kind, let from, let to):
            let start = TimelineMarkLayout.x(of: from, in: range, width: width)
            let end = TimelineMarkLayout.x(of: to, in: range, width: width)
            Capsule()
                .fill(kind == .red ? Theme.flagRed : Theme.flagYellow)
                .frame(width: max(end - start, 2), height: 3)
                .offset(x: start, y: 1.5)
        case .lightsOut(let at, _):
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: TimelineMarksStrip.height)
                .offset(x: TimelineMarkLayout.x(of: at, in: range, width: width) - 1)
        case .chequered(let at):
            ChequerGlyph()
                .offset(x: TimelineMarkLayout.x(of: at, in: range, width: width) - 3)
        }
    }
}

/// A 6 pt chequered square.
private struct ChequerGlyph: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.white.frame(width: 3, height: 3)
                Color.black.frame(width: 3, height: 3)
            }
            HStack(spacing: 0) {
                Color.black.frame(width: 3, height: 3)
                Color.white.frame(width: 3, height: 3)
            }
        }
    }
}

// MARK: - Notice

/// One line in the middle, as Android's status line: tap to dismiss; it also clears itself.
struct MultiviewNoticeView: View {
    let controller: MultiviewController

    var body: some View {
        ZStack {
            if let text = controller.notice {
                notice(text)
            }
        }
        .animation(.easeOut(duration: 0.2), value: controller.notice)
    }

    private func notice(_ text: String) -> some View {
        Button {
            controller.dismissNotice()
        } label: {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: 420)
        }
        .buttonStyle(.plain)
        .padding(24)
        .transition(.opacity)
    }
}

// MARK: - Text

enum MultiviewClock {
    /// "m:ss", or "h:mm:ss" from an hour, as the Android app's clock.
    static func text(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(Int(seconds.rounded(.down)), 0) : 0
        let hours = total / 3_600
        let minutes = total / 60 % 60
        let secs = total % 60
        let twoDigits: (Int) -> String = { $0 < 10 ? "0\($0)" : "\($0)" }
        if hours > 0 { return "\(hours):\(twoDigits(minutes)):\(twoDigits(secs))" }
        return "\(minutes):\(twoDigits(secs))"
    }

    /// "1×", "0.75×", "2×", whatever the locale: a fixed format (no locale), like `SyncPolicy`.
    static func speedText(_ speed: Double) -> String {
        String(format: "%g", speed) + "×"
    }
}

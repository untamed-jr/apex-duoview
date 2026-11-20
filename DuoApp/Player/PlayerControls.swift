import AVKit
import Multiview
import SwiftUI

/// The single-feed player's own controls (owner, 2026-11-20, option B: instead of AVKit's, which
/// doubled the ✕ and Map, had a LIVE label that didn't go live, and could stay stuck on screen).
/// The same look as the multiview's:
///
/// - Top: one ✕ and mute; on the right, Map and Radio (only with timing), picture in picture (when
///   it can start) and AirPlay.
/// - Bottom: the scrubber with the elapsed and remaining time (live: how far behind), play/pause,
///   back and forward 10 s, LIVE for live video (red at the live point; outlined behind it, and a
///   tap goes live), the speed (not at the live point), and one menu for the commentary language
///   and subtitles (only when there is a choice), as Apple's menu was.
///
/// They hide 4 s after the last touch and a tap on the picture brings them back (a tap while they
/// show hides them). Held up while paused, loading or scrubbing. The map and tower panels sit
/// between the picture's tap layer and the bars, so they take their own touches. The onboard's
/// driver card stays under the top bar whether or not the controls show.
///
/// Picture in picture also starts by itself on leaving the app while a video plays.
struct PlayerChrome: View {
    let controller: PlayerController
    let fold: FoldState

    @State private var shown = true
    /// Bumped by every use of the controls: the 4 s start again.
    @State private var touch = 0

    static let hideDelay: Double = 4

    private struct HideTimer: Equatable {
        var touch: Int
        var shown: Bool
        var pinned: Bool
    }

    var body: some View {
        let transport = controller.transport
        let ready = controller.player != nil && !controller.isLoading
        let pinned = transport.isPaused || controller.isLoading || transport.scrubbing
        ZStack {
            if ready {
                // The picture: a tap shows or hides the controls.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { toggle(pinned: pinned) }
                    .accessibilityElement()
                    .accessibilityLabel(shown ? "Hide controls" : "Show controls")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { toggle(pinned: pinned) }
                ExternalPlaybackNote(transport: transport)
                PlayerPanelsLayer(controller: controller, fold: fold, onInteraction: noteUse)
            }
            VStack(spacing: 0) {
                PlayerTopBar(controller: controller, showsTiming: ready, onInteraction: noteUse)
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(shown)
                    .accessibilityHidden(!shown)
                if ready {
                    HStack {
                        PlayerCardLayer(controller: controller)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                }
                Spacer(minLength: 0)
                if ready {
                    PlayerPlaybackBar(controller: controller, transport: transport, onInteraction: noteUse)
                        .opacity(shown ? 1 : 0)
                        .allowsHitTesting(shown)
                        .accessibilityHidden(!shown)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: shown)
        .task(id: HideTimer(touch: touch, shown: shown, pinned: pinned)) {
            guard shown, !pinned else { return }
            try? await Task.sleep(for: .seconds(Self.hideDelay))
            guard !Task.isCancelled else { return }
            shown = false
        }
        // Paused, loading or scrubbing: up, until that ends (then 4 s more).
        .onChange(of: pinned) { _, isPinned in
            if isPinned { shown = true }
        }
    }

    private func toggle(pinned: Bool) {
        if shown, !pinned {
            shown = false
        } else {
            shown = true
            touch += 1
        }
    }

    /// A use of a control or a panel while the controls show: another 4 s.
    private func noteUse() {
        if shown { touch += 1 }
    }
}

// MARK: - Top bar

/// ✕ on the left; Map and AirPlay on the right.
private struct PlayerTopBar: View {
    let controller: PlayerController
    /// Playing (not loading): Map and AirPlay show. ✕ always does.
    let showsTiming: Bool
    let onInteraction: @MainActor () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 8) {
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
                if showsTiming {
                    MuteButton(controller: controller, transport: controller.transport,
                               onInteraction: onInteraction)
                }
                Spacer(minLength: 8)
                if showsTiming {
                    TimingMapButton(timing: controller.timing, onInteraction: onInteraction)
                        .appTip(TapCarTip())
                    RadioButton(radio: controller.radio, timing: controller.timing, onInteraction: onInteraction)
                    PictureInPictureButton(controller: controller, transport: controller.transport)
                    AirPlayButton()
                        .frame(width: 32, height: 32)
                        .videoGlass(in: Circle())
                        .frame(width: 44, height: 44)
                        .simultaneousGesture(TapGesture().onEnded { onInteraction() })
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }
}

/// Starts picture in picture; shown only when it can start.
private struct PictureInPictureButton: View {
    let controller: PlayerController
    let transport: PlayerTransport

    var body: some View {
        if transport.canPictureInPicture {
            Button {
                controller.startPictureInPicture()
            } label: {
                Image(systemName: "pip.enter")
                    .font(.footnote.bold())
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .videoGlass(in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Picture in picture")
        }
    }
}

/// While the video plays on an AirPlay screen, the picture here is black: one line says why.
private struct ExternalPlaybackNote: View {
    let transport: PlayerTransport

    var body: some View {
        if transport.isExternal {
            Label("Playing on AirPlay", systemImage: "airplayvideo")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .allowsHitTesting(false)
        }
    }
}

/// Sound off or on: the app's own (the iPhone's side buttons set the volume).
private struct MuteButton: View {
    let controller: PlayerController
    let transport: PlayerTransport
    let onInteraction: @MainActor () -> Void

    var body: some View {
        let muted = transport.isMuted
        Button {
            controller.toggleMute()
            onInteraction()
        } label: {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.footnote.bold())
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .videoGlass(in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(muted ? "Sound off. Turn sound on" : "Mute")
    }
}

/// Apple's AirPlay picker, white on the glass, red while the video plays elsewhere.
private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = .white
        picker.activeTintColor = UIColor(Theme.accent)
        picker.accessibilityLabel = "AirPlay"
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Bottom panel

/// The scrubber over play/pause, −10/+10, LIVE, speed and commentary language. Reads only the
/// transport, so its twice-a-second changes redraw this panel alone.
private struct PlayerPlaybackBar: View {
    let controller: PlayerController
    let transport: PlayerTransport
    let onInteraction: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let range = transport.timeline, range.upperBound - range.lowerBound >= 1 {
                PlayerScrubber(controller: controller, transport: transport, range: range, onInteraction: onInteraction)
            }
            HStack(spacing: 4) {
                skipButton(-10)
                playButton
                skipButton(10)
                if transport.isLive {
                    liveButton
                        .padding(.leading, 4)
                }
                Spacer(minLength: 8)
                if !transport.isAtLiveEdge {
                    speedMenu
                }
                if transport.audioOptions.count > 1 || !transport.subtitleOptions.isEmpty {
                    audioMenu
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .videoGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: 640)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var playButton: some View {
        let paused = transport.isPaused
        return Button {
            controller.togglePlay()
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

    /// Back or forward 10 s. Forward is off at the live point (there is nothing ahead).
    private func skipButton(_ seconds: Double) -> some View {
        let forward = seconds > 0
        let disabled = forward && transport.isAtLiveEdge
        return Button {
            controller.skip(by: seconds)
            onInteraction()
        } label: {
            Image(systemName: forward ? "goforward.10" : "gobackward.10")
                .font(.title3)
                .foregroundStyle(.white.opacity(disabled ? 0.35 : 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(forward ? "Forward 10 seconds" : "Back 10 seconds")
    }

    /// Red at the live point; behind it, an outlined LIVE that goes back there.
    private var liveButton: some View {
        let atEdge = transport.isAtLiveEdge
        return Button {
            controller.goLive()
            onInteraction()
        } label: {
            Group {
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
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(atEdge ? "Live" : "Go live")
    }

    private var speedMenu: some View {
        let current = transport.rate
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
        .simultaneousGesture(TapGesture().onEnded { onInteraction() })
        .accessibilityLabel("Speed \(MultiviewClock.speedText(current))")
    }

    /// Commentary language and subtitles in one menu. Its label is the commentary language, or
    /// "Subtitles" when there is only one commentary.
    private var audioMenu: some View {
        let options = transport.audioOptions
        let selected = transport.selectedAudioOption
        let subtitles = transport.subtitleOptions
        let subtitle = transport.selectedSubtitle
        let hasAudioChoice = options.count > 1
        let chosenName = hasAudioChoice
            ? options.first(where: { $0.id == selected })?.name ?? "Audio"
            : "Subtitles"
        return Menu {
            if hasAudioChoice {
                Section("Commentary") {
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
            }
            if !subtitles.isEmpty {
                Section("Subtitles") {
                    if transport.subtitlesCanBeOff {
                        Button {
                            controller.selectSubtitle(nil)
                            onInteraction()
                        } label: {
                            if subtitle == nil {
                                Label("Off", systemImage: "checkmark")
                            } else {
                                Text("Off")
                            }
                        }
                    }
                    ForEach(subtitles) { option in
                        Button {
                            controller.selectSubtitle(option.id)
                            onInteraction()
                        } label: {
                            if option.id == subtitle {
                                Label(option.name, systemImage: "checkmark")
                            } else {
                                Text(option.name)
                            }
                        }
                    }
                }
            }
        } label: {
            Label(chosenName, systemImage: hasAudioChoice ? "waveform" : "captions.bubble")
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
        .accessibilityLabel(hasAudioChoice ? "Audio and subtitles, \(chosenName)" : "Subtitles")
    }
}

/// Dragging previews the time; letting go seeks once (no seeking while the finger moves).
private struct PlayerScrubber: View {
    let controller: PlayerController
    let transport: PlayerTransport
    let range: ClosedRange<Double>
    let onInteraction: @MainActor () -> Void

    @State private var preview: Double?

    var body: some View {
        let lower = range.lowerBound
        let shown: Double = min(max(preview ?? transport.position, lower), range.upperBound)
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
        .onDisappear {
            preview = nil
            transport.scrubbing = false
        }
    }

    /// The time left in a replay; live, how far behind the live point (nothing when at it).
    private func trailingText(shown: Double) -> String {
        let left = max(range.upperBound - shown, 0)
        if transport.isLive, left <= MultiviewController.liveEdgeSlack { return "" }
        return "−" + MultiviewClock.text(left)
    }

    private func editingChanged(_ editing: Bool) {
        if editing {
            transport.scrubbing = true
        } else {
            if let preview { controller.seek(toSeconds: preview) }
            preview = nil
            transport.scrubbing = false
        }
        onInteraction()
    }
}

// MARK: - Panels and card

/// The floating panels over the picture (map, tower, team radio), only while one shows. Its own
/// view: the chrome's body never reads the timing or the radio.
private struct PlayerPanelsLayer: View {
    let controller: PlayerController
    let fold: FoldState
    let onInteraction: @MainActor () -> Void

    var body: some View {
        let timing = controller.timing
        let radio = controller.radio
        if timing.showsData, !timing.panels.isEmpty || radio.panelShown {
            GeometryReader { proxy in
                FloatingPanels(
                    timing: timing,
                    radio: radio,
                    bounds: CGRect(origin: .zero, size: proxy.size),
                    postureKey: PanelLayout.postureKey(posture: fold.posture.rawValue, size: proxy.size),
                    onCar: { number in
                        onInteraction()
                        // Racing numbers are whole numbers; anything else has no onboard.
                        guard let racingNumber = Int(number) else { return }
                        Task { await controller.showOnboard(racingNumber: racingNumber) }
                    })
            }
        }
    }
}

/// The onboard's driver card, under the top bar: its own view, so the chrome's body never reads
/// the 2 Hz values. Long-press it for "Hide card".
private struct PlayerCardLayer: View {
    let controller: PlayerController

    var body: some View {
        if let onboard = controller.onboard, controller.timing.showsData {
            DriverCardSlot(timing: controller.timing, channelId: onboard.channelId, number: onboard.number)
        }
    }
}

import AVFoundation
import Observation

/// What the single-feed player's own controls show (owner, 2026-11-19, option B: the app's controls
/// instead of AVKit's): playing or paused, the scrubber's span and place, live and how far behind
/// it, the speed and the audio choices. `PlayerController` refreshes it twice a second; only values
/// that changed are written, so the controls redraw only when they must, and the cover's body never
/// reads it.
@MainActor @Observable
final class PlayerTransport {
    /// Read from the player's own state, so a pause from picture in picture, the lock screen or
    /// headphones shows here too.
    private(set) var isPaused = true
    /// The playhead, in the item's seconds.
    private(set) var position: Double = 0
    /// The scrubber's span: 0…duration for a replay, the rewind window ending at the live point
    /// live. nil until known.
    private(set) var timeline: ClosedRange<Double>?
    private(set) var isLive = false
    /// Seconds behind the live point (live only).
    private(set) var behindLive: Double?
    private(set) var rate: Double = 1
    private(set) var audioOptions: [MultiviewAudioOption] = []
    private(set) var selectedAudioOption: Int?
    /// The video's subtitle languages (forced-only tracks left out); ids are the indices in its
    /// legible group. Empty when it has none.
    private(set) var subtitleOptions: [MultiviewAudioOption] = []
    /// nil: subtitles off.
    private(set) var selectedSubtitle: Int?
    /// The group allows no subtitles at all ("Off" in the menu).
    private(set) var subtitlesCanBeOff = true
    private(set) var isMuted = false
    /// The scrubber is held: the controls stay up.
    var scrubbing = false

    /// At (or near enough) the live point: LIVE is red and the speed menu hides, as in multiview.
    var isAtLiveEdge: Bool {
        isLive && (behindLive ?? 0) <= MultiviewController.liveEdgeSlack
    }

    /// A new item, or none: everything back to its start.
    func reset() {
        if !isPaused { isPaused = true }
        if position != 0 { position = 0 }
        if timeline != nil { timeline = nil }
        if isLive { isLive = false }
        if behindLive != nil { behindLive = nil }
        if rate != 1 { rate = 1 }
        if !audioOptions.isEmpty { audioOptions = [] }
        if selectedAudioOption != nil { selectedAudioOption = nil }
        if !subtitleOptions.isEmpty { subtitleOptions = [] }
        if selectedSubtitle != nil { selectedSubtitle = nil }
        if !subtitlesCanBeOff { subtitlesCanBeOff = true }
        scrubbing = false
    }

    /// Reads the player. While a seek is under way the player may still report the old place, so
    /// `heldPosition` (the seek's target) wins until it lands.
    func update(player: AVPlayer, heldPosition: Double?) {
        let paused = player.timeControlStatus == .paused
        if isPaused != paused { isPaused = paused }
        guard let item = player.currentItem else { return }
        let now = player.currentTime()
        if let heldPosition {
            if position != heldPosition { position = heldPosition }
        } else if now.isNumeric, now.seconds.isFinite, position != now.seconds {
            position = now.seconds
        }
        let duration = item.duration
        let live = duration.isIndefinite
        if isLive != live { isLive = live }
        var span: ClosedRange<Double>?
        if live {
            span = MultiviewController.liveWindow(item)
        } else if duration.isNumeric, duration.seconds.isFinite, duration.seconds > 0 {
            span = 0...duration.seconds
        }
        if timeline != span { timeline = span }
        var behind: Double?
        if live, let span { behind = max(span.upperBound - position, 0) }
        if behindLive != behind { behindLive = behind }
    }

    func setRate(_ newRate: Double) {
        if rate != newRate { rate = newRate }
    }

    func setSubtitles(options: [MultiviewAudioOption], selected: Int?, canBeOff: Bool) {
        if subtitleOptions != options { subtitleOptions = options }
        if selectedSubtitle != selected { selectedSubtitle = selected }
        if subtitlesCanBeOff != canBeOff { subtitlesCanBeOff = canBeOff }
    }

    /// Kept across feeds (`reset` leaves it): the controller re-applies it to each new player.
    func setMuted(_ muted: Bool) {
        if isMuted != muted { isMuted = muted }
    }

    func setAudio(options: [MultiviewAudioOption], selected: Int?) {
        if audioOptions != options { audioOptions = options }
        if selectedAudioOption != selected { selectedAudioOption = selected }
    }
}

/// Carries a loaded selection group from AVFoundation's callback queue to the main actor, which
/// alone reads it from then on. Unchecked so it compiles whether or not the SDK marks the group
/// Sendable.
final class PlayerAudioGroupBox: @unchecked Sendable {
    let group: AVMediaSelectionGroup?

    init(_ group: AVMediaSelectionGroup?) {
        self.group = group
    }
}

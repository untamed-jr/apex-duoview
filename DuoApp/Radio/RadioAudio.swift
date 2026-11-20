import AVFoundation
import Foundation

/// Plays team radio clips: one `AVAudioEngine` with an `AVAudioPlayerNode` → an
/// `AVAudioMixerNode` (stereo out, so a mono clip can be panned) → an `AVAudioUnitTimePitch`
/// (rate = the feeds' speed, the pitch kept) → the main mixer. Pan and volume are on the player
/// node: they apply at the submixer's input bus (mixing settings only apply at a mixer's input).
/// The engine runs only while a clip plays, and starts again for the next clip after a
/// configuration change (a route or format change stops it) or an audio interruption (a call,
/// Siri); the clip playing then ends, so the feeds get their sound back.
///
/// It plays in the app's audio session (`.playback`, set by the players), alongside the feeds.
@MainActor
final class RadioAudio: RadioPlayback {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    /// Where the node's pan and volume apply.
    private let submixer = AVAudioMixerNode()
    private let pitch = AVAudioUnitTimePitch()
    /// The format the nodes are connected with (the last clip's), so a clip in another format
    /// reconnects them.
    private var connected: AVAudioFormat?
    /// Bumped by every play and stop: the node's completion for an older clip (it also comes on
    /// `stop()`) is dropped.
    private var token = 0
    private var onEnd: (@MainActor () -> Void)?
    private var observer: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    init() {
        engine.attach(node)
        engine.attach(submixer)
        engine.attach(pitch)
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { @Sendable [weak self] _ in
            MainActor.assumeIsolated { self?.stoppedBySystem() }
        }
        // A call or Siri stops the engine without the clip's end being reported.
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main
        ) { @Sendable [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
            MainActor.assumeIsolated {
                if began { self?.stoppedBySystem() }
            }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        node.stop()
        engine.stop()
    }

    func play(fileURL: URL, pan: Float, rate: Float, onEnd: @escaping @MainActor () -> Void) throws {
        stop()
        let file = try AVAudioFile(forReading: fileURL)
        guard file.length > 0 else { throw RadioAudioError.empty }
        let format = file.processingFormat
        if connected != format {
            // Stereo out of the submixer, at the clip's rate, so a mono clip can be panned.
            guard let stereo = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2) else {
                throw RadioAudioError.format
            }
            // Reconnected only while stopped.
            engine.stop()
            engine.disconnectNodeOutput(node)
            engine.disconnectNodeOutput(submixer)
            engine.disconnectNodeOutput(pitch)
            engine.connect(node, to: submixer, format: format)
            engine.connect(submixer, to: pitch, format: stereo)
            engine.connect(pitch, to: engine.mainMixerNode, format: stereo)
            connected = format
        }
        pitch.rate = Self.clamped(rate)
        node.pan = min(max(pan, -1), 1)
        node.volume = 1
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
        token &+= 1
        let mine = token
        self.onEnd = onEnd
        node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in self?.finished(token: mine) }
        }
        node.play()
    }

    func setRate(_ rate: Float) {
        let value = Self.clamped(rate)
        if pitch.rate != value { pitch.rate = value }
    }

    func stop() {
        token &+= 1
        onEnd = nil
        node.stop()
        if engine.isRunning { engine.stop() }
    }

    private func finished(token mine: Int) {
        guard token == mine, let onEnd else { return }
        self.onEnd = nil
        node.stop()
        if engine.isRunning { engine.stop() }
        onEnd()
    }

    var isPlaying: Bool {
        onEnd != nil && engine.isRunning
    }

    /// The system stopped the engine (a route or format change, or an interruption): the clip
    /// ends; the next one connects and starts the engine again.
    private func stoppedBySystem() {
        connected = nil
        let ending = onEnd
        token &+= 1
        onEnd = nil
        node.stop()
        if engine.isRunning { engine.stop() }
        ending?()
    }

    /// The time-pitch unit's range.
    private static func clamped(_ rate: Float) -> Float {
        guard rate.isFinite else { return 1 }
        return min(max(rate, 1.0 / 32), 32)
    }
}

enum RadioAudioError: Error {
    case empty
    case format
}

extension RadioController {
    /// The app's player for clips.
    static func defaultAudio() -> any RadioPlayback {
        RadioAudio()
    }
}

import AVFoundation
import Foundation

/// Plays team radio clips: one `AVAudioEngine` with an `AVAudioPlayerNode` → an
/// `AVAudioUnitTimePitch` (rate = the feeds' speed, the pitch kept) → the main mixer. Pan and
/// volume are on the player node. The engine runs only while a clip plays, and starts again after
/// a configuration change (a route or format change stops it); the clip playing then ends.
///
/// It plays in the app's audio session (`.playback`, set by the players), alongside the feeds.
@MainActor
final class RadioAudio: RadioPlayback {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let pitch = AVAudioUnitTimePitch()
    /// The format the nodes are connected with (the last clip's), so a clip in another format
    /// reconnects them.
    private var connected: AVAudioFormat?
    /// Bumped by every play and stop: the node's completion for an older clip (it also comes on
    /// `stop()`) is dropped.
    private var token = 0
    private var onEnd: (@MainActor () -> Void)?
    private var observer: NSObjectProtocol?

    init() {
        engine.attach(node)
        engine.attach(pitch)
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { @Sendable [weak self] _ in
            MainActor.assumeIsolated { self?.configurationChanged() }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        node.stop()
        engine.stop()
    }

    func play(fileURL: URL, pan: Float, rate: Float, onEnd: @escaping @MainActor () -> Void) throws {
        stop()
        let file = try AVAudioFile(forReading: fileURL)
        guard file.length > 0 else { throw RadioAudioError.empty }
        let format = file.processingFormat
        if connected != format {
            // Reconnected only while stopped.
            engine.stop()
            engine.disconnectNodeOutput(node)
            engine.disconnectNodeOutput(pitch)
            engine.connect(node, to: pitch, format: format)
            engine.connect(pitch, to: engine.mainMixerNode, format: format)
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

    /// The system stopped the engine (a route or format change): the clip ends; the next one
    /// starts the engine again.
    private func configurationChanged() {
        connected = nil
        let ending = onEnd
        token &+= 1
        onEnd = nil
        node.stop()
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
}

extension RadioController {
    /// The app's player for clips.
    static func defaultAudio() -> any RadioPlayback {
        RadioAudio()
    }
}

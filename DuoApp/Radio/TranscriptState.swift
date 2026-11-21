import Foundation
import LiveTiming

// Transcripts' plain values and words: whether the phone can transcribe, the Radio panel's line
// for it, a row's transcript text, and the words the transcriber leans toward. No Speech, no
// SwiftUI and no actor isolation, so the harness checks all of it.

/// Whether the phone's own speech recognition can turn clips into text now.
enum TranscriberReadiness: Sendable, Equatable {
    case ready
    /// iOS is downloading its English speech model (a system download, shared by all apps).
    case downloadingModel
    /// No on-device English engine: clips still play, without text.
    case unavailable
    /// Speech recognition was turned off for the app in Settings.
    case permissionDenied
}

/// Why a clip wasn't transcribed, when it isn't the clip's fault: the controller stops asking
/// (the clip is `cancelled`, not failed) and shows the panel's line.
enum TranscriberError: Error, Equatable {
    case permissionDenied
    case unavailable
}

/// What the transcriber the controller drives does (`Transcriber` in the app, a fake in checks).
protocol RadioTranscribing: Sendable {
    /// Ready, or why not; quick (a model download runs in the background and reads
    /// `.downloadingModel` until it's done). Asked again until it's `.ready`.
    func prepare() async -> TranscriberReadiness
    /// The clip's words, on the phone only. Blank means no words (the queue stores
    /// `TranscriptionQueue.noWords`). Throws `TranscriberError` when transcripts can't run at all.
    func transcribe(fileURL: URL, hints: [String]) async throws -> String
}

enum TranscriptState {
    // MARK: Copy

    static let downloading = "Getting the speech model ready\u{2026}"
    static let unavailable = "Transcripts aren't available on this iPhone \u{2014} clips still play"
    static let permissionDenied = "Allow speech recognition in Settings to see transcripts"

    /// The Radio panel's line for `readiness`; nil when ready.
    static func line(for readiness: TranscriberReadiness) -> String? {
        switch readiness {
        case .ready: return nil
        case .downloadingModel: return downloading
        case .unavailable: return unavailable
        case .permissionDenied: return permissionDenied
        }
    }

    /// The row's transcript as shown: the words in quotes, "Transcribing…", "(no words
    /// recognised)", or nothing. The row draws at most two lines of it.
    static func rowText(_ line: TranscriptLine) -> String? {
        switch line {
        case .none: return nil
        case .transcribing: return RadioModels.transcribing
        case .noWords: return TranscriptionQueue.noWords
        case .text(let words): return "\u{201C}\(words)\u{201D}"
        }
    }

    // MARK: Hints

    /// What engineers and drivers say a lot (Android's `RadioTranscriber.RADIO_WORDS`).
    static let radioWords = [
        "box", "box box", "copy", "copy that", "understood", "tyres", "softs", "mediums", "hards",
        "inters", "DRS", "safety car", "virtual safety car", "VSC", "yellow flag", "red flag",
        "blue flags", "track limits", "penalty", "five second penalty", "gap", "pace", "push",
        "stay out", "pit", "pit stop", "undercut", "overcut", "deg", "degradation", "graining",
        "brake bias", "diff", "strat", "plan A", "plan B", "mode push", "lift and coast",
        "good job", "well done", "P1", "P2", "P3", "lap", "sector", "turn", "engine", "battery",
    ]

    /// Android sends at most this many.
    static let maxHints = 100

    /// The session's drivers' last and first names (in racing-number order), its teams, then the
    /// radio words: blanks and repeats left out, at most `maxHints`.
    static func hints(drivers: [String: DriverInfo]) -> [String] {
        let cars = drivers.values.sorted { ($0.number.count, $0.number) < ($1.number.count, $1.number) }
        var seen: Set<String> = []
        var out: [String] = []
        for word in cars.flatMap({ [$0.lastName, $0.firstName] }) + cars.map(\.teamName) + radioWords {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            out.append(trimmed)
            if out.count == maxHints { break }
        }
        return out
    }
}

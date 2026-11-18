import Foundation

/// Which radio clip to turn into text next, and what came of each: the rules of Android's
/// transcription loop (`AppState.transcribeRadio`), as a value the app's transcriber drives.
/// It holds no clips and runs nothing; the app asks `next`, transcribes that clip, and reports
/// back with `finished`, `failed` or `timedOut`.
///
/// - One clip at a time: `next` gives nothing while one is running.
/// - Nearest the picture first: of the clips without a result, not skipped and published no more
///   than 2 minutes after picture time (behind it, any distance), the one whose `Utc` is closest
///   to it; on a tie, the earlier in the list.
/// - A clip not done 45 s after it started is skipped (`next` does it once the 45 s are up, or
///   the app calls `timedOut`). A skip isn't a failure: it doesn't count towards the three.
/// - Three failures in a row wait 2 minutes, then try the failed and skipped clips again.
///   A result ends the run.
/// - Results are kept by clip path, so a clip with one is never queued again (seed `results`
///   with the kept transcripts). Nothing recognised is a result: `noWords`.
///
/// `now` is the wall clock (ms), never picture time: the 45 s and the 2 minutes run while the
/// picture is paused.
public struct TranscriptionQueue: Sendable, Equatable {
    /// How far past picture time clips are transcribed early, so their text is ready.
    public static let aheadMs: Int64 = 120_000
    /// How long one clip may take before it's skipped.
    public static let timeoutMs: Int64 = 45_000
    /// Failures in a row before waiting.
    public static let failuresBeforeWait = 3
    /// How long to wait after them.
    public static let waitMs: Int64 = 120_000
    /// What a clip with nothing recognised stores.
    public static let noWords = "(no words recognised)"

    /// The clip being transcribed and when (wall clock) it started.
    public struct Job: Sendable, Equatable {
        public var path: String
        public var startedAt: Int64
    }

    /// Transcripts by clip path.
    public private(set) var results: [String: String]
    public private(set) var running: Job?
    /// Clips that failed or timed out, not tried again until a wait ends.
    public private(set) var skipped: Set<String> = []
    public private(set) var failuresInRow = 0
    /// While waiting after three failures: when the wait ends (wall clock).
    public private(set) var waitingUntil: Int64?

    public init(results: [String: String] = [:]) {
        self.results = results
    }

    /// The path being transcribed ("Transcribing…"), if any.
    public var transcribing: String? { running?.path }

    /// The clip to transcribe now, marked as running from `now`; nil while one runs, while
    /// waiting, or when no clip is due. `pictureTime` is picture time; `clips` are the session's.
    public mutating func next(from clips: [RadioClip], at pictureTime: UTCms, now: Int64) -> RadioClip? {
        if let running {
            guard F1Values.sub(now, running.startedAt) >= Self.timeoutMs else { return nil }
            timedOut(path: running.path)
        }
        if let waitingUntil {
            guard now >= waitingUntil else { return nil }
            self.waitingUntil = nil
        }
        let limit = F1Values.add(pictureTime, Self.aheadMs)
        var best: RadioClip?
        var bestDistance: Int64 = .max
        for clip in clips where clip.utc <= limit && results[clip.path] == nil && !skipped.contains(clip.path) {
            let distance = clip.utc > pictureTime ? F1Values.sub(clip.utc, pictureTime) : F1Values.sub(pictureTime, clip.utc)
            if best == nil || distance < bestDistance {
                best = clip
                bestDistance = distance
            }
        }
        if let best { running = Job(path: best.path, startedAt: now) }
        return best
    }

    /// The text for `path`; blank (once trimmed) is `noWords`. Kept even when it arrives after
    /// the clip was skipped. Ends a run of failures.
    public mutating func finished(path: String, result: String) {
        let text = result.trimmingCharacters(in: .whitespacesAndNewlines)
        results[path] = text.isEmpty ? Self.noWords : text
        if running?.path == path { running = nil }
        failuresInRow = 0
    }

    /// The running clip failed at `now` (wall clock). It's skipped; the third failure in a row
    /// starts a 2-minute wait, after which the skipped clips are tried again. A report for a clip
    /// that isn't running (it timed out first) changes nothing.
    public mutating func failed(path: String, at now: Int64) {
        guard running?.path == path else { return }
        running = nil
        skipped.insert(path)
        failuresInRow += 1
        if failuresInRow >= Self.failuresBeforeWait {
            failuresInRow = 0
            skipped.removeAll()
            waitingUntil = F1Values.add(now, Self.waitMs)
        }
    }

    /// The running clip took too long: skipped, not counted as a failure.
    public mutating func timedOut(path: String) {
        guard running?.path == path else { return }
        running = nil
        skipped.insert(path)
    }
}

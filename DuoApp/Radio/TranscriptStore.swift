import Foundation

/// A session's transcripts, kept so a replay isn't transcribed twice: `[clip path: transcript]`
/// as `transcripts.json` beside the session's clips (`Caches/radio/{sessionKey}/`), deleted with
/// them after 7 days (`RadioFetch.deleteExpired`). The queue is seeded from it with
/// `TranscriptionQueue(results:)`.
///
/// Pure (Foundation only, no actor): the controller reads and writes it off the main actor. A
/// missing, unreadable or corrupt file reads as empty; a failed write is dropped (the clips are
/// transcribed again next time).
struct TranscriptStore: Sendable, Equatable {
    static let fileName = "transcripts.json"

    let url: URL

    init(url: URL) {
        self.url = url
    }

    /// `base/{sessionKey}/transcripts.json`, the key made safe as the clips' folder is.
    init(base: URL, sessionKey: String) {
        url = RadioFetch.folder(base: base, sessionKey: sessionKey)
            .appendingPathComponent(Self.fileName, isDirectory: false)
    }

    func load() -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let transcripts = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return transcripts
    }

    /// Writes all of them at once (atomically); false when it couldn't.
    @discardableResult
    func save(_ transcripts: [String: String]) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(transcripts)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

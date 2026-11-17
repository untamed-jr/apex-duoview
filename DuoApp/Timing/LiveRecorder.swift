import Foundation
import LiveTiming

/// The live recording (0.99.4, adapted): while a live session's timing is followed, every
/// recorded topic (`LiveRecording`: all but CarData.z and Heartbeat) is appended to
/// `Caches/live/{sessionKey}.txt` in Android's line format, flushed every 2 s. Reopening the same
/// session appends to its file (after a line break, in case the last write was cut off); a new
/// session starts its file afresh. A rewind of a live session reads what was recorded, through
/// `LiveConnection`, which replays it to every new listener. Files older than 7 days are
/// deleted at launch (`deleteOld`).
///
/// The file holds only F1's timing messages: never a token, cookie or URL. Never logs. A write
/// that fails (the disk full, the folder gone) drops those lines rather than holding them.
actor LiveRecorder {
    private let directory: URL?
    /// The file being recorded to; nil while none is open.
    private var file: URL?
    /// Lines not yet written, the append prefix first.
    private var pending = ""
    private var flushTask: Task<Void, Never>?

    /// `directory`: where the files go; Caches/live unless a check says otherwise.
    init(directory: URL? = LiveRecorder.defaultDirectory) {
        self.directory = directory
    }

    /// `Caches/live/`: the system may clear it, and the archive has the session again later.
    nonisolated static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("live", isDirectory: true)
    }

    /// The file recorded to now, if any (for checks).
    var currentFile: URL? { file }

    /// Opens the recording for a session (its SessionInfo `Key` and `Path`): when the file is
    /// this session's it is appended to and its messages so far come back (the earlier visit);
    /// otherwise it is started afresh and nothing comes back. Whatever the previous session
    /// left unwritten is written first.
    func begin(sessionKey: Int?, sessionPath: String) -> [RecordedMessage] {
        flush()
        file = nil
        guard let directory else { return [] }
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(LiveRecordingFiles.fileName(sessionKey: sessionKey, path: sessionPath))
        switch LiveRecording.start(existingHead: Self.head(of: url), sessionPath: sessionPath) {
        case .append(let prefix):
            file = url
            pending = prefix
            guard let data = try? Data(contentsOf: url) else { return [] }
            return LiveRecording.read(data).messages
        case .fresh(let header):
            guard manager.createFile(atPath: url.path, contents: Data(header.utf8)) else { return [] }
            file = url
            pending = ""
            return []
        }
    }

    /// Queues the recorded topics' lines; they are written within 2 s.
    func record(_ messages: [RecordedMessage]) {
        guard file != nil else { return }
        let text = LiveRecording.lines(messages)
        guard !text.isEmpty else { return }
        pending += text
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: LiveRecordingFiles.flushInterval)
            await self?.flushDue()
        }
    }

    /// Writes what is queued and closes the file (nobody is listening any more).
    func end() {
        flush()
        file = nil
    }

    private func flushDue() {
        flushTask = nil
        flush()
    }

    /// Appends what is queued to the file.
    func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard let file, !pending.isEmpty else { return }
        let text = pending
        pending = ""
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        } catch {
            // Dropped: the archive top-up fills the session in later.
        }
    }

    /// The file's first bytes (enough for its header), nil when there is no file.
    private static func head(of url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: LiveRecordingFiles.headBytes)
    }

    /// Deletes recordings last written more than 7 days before `now`.
    nonisolated static func deleteOld(in directory: URL?, now: Date) {
        guard let directory else { return }
        let manager = FileManager.default
        guard let urls = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        for url in urls {
            let written = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let written, LiveRecordingFiles.isOld(written: written, now: now) {
                try? manager.removeItem(at: url)
            }
        }
    }
}

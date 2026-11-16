import Foundation
import LiveTiming
#if canImport(Network)
import Network
#endif

/// The car data behind the speed readouts (CarData.z, owner option A): downloaded in the
/// background as soon as an onboard card shows, kept in the app's Caches as
/// `cardata/{sessionKey}.jsonStream` (deleted after 7 days), so scrubbing back never fetches it
/// again. Only a ±60 s window around picture time is parsed and held in memory.
///
/// - The download goes through `TimingArchive.byteRange` (the token, the archive's host only, a
///   refusal never signs anyone out), 1 MiB at a time. A server that ignores the range answers
///   with the whole file (a 200, no Content-Range): that one download is kept and the ranges stop.
/// - A refusal or a missing file (401/403/404) stops it quietly: the readouts stay hidden. A
///   network failure tries the same piece again after 3, 10, 30 and 60 s, then every 60 s.
/// - With "Speed readouts on mobile data" off, it waits between pieces while the connection is
///   expensive (`NWPathMonitor`'s `isExpensive`), and goes on once it isn't.
///
/// Never logs; the token stays inside `TimingArchive`.
@MainActor
final class CarDataLoader {
    /// The archive's file.
    nonisolated static let fileName = "CarData.z.jsonStream"
    /// Each byte range asked for.
    nonisolated static let chunkBytes = 1 << 20
    /// The window held in memory reaches this far either side of picture time.
    nonisolated static let windowMs: Int64 = 60_000
    /// Extra lines read beyond the window: a line's samples carry their own Utc, a little before
    /// the line's time.
    nonisolated static let windowPadMs: Int64 = 5_000
    /// The window is read again once picture time comes this close to one of its edges.
    nonisolated static let windowReloadMarginMs: Int64 = 20_000
    /// Files older than this are deleted.
    nonisolated static let keepFor: TimeInterval = 7 * 24 * 3600
    /// The waits between tries of a piece that failed; the last repeats (as the timing load's).
    nonisolated static let retryDelays: [Duration] = [.seconds(3), .seconds(10), .seconds(30), .seconds(60)]

    private let download: CarDataDownload
    private let streamStart: UTCms
    private var task: Task<Void, Never>?
    /// What the download has written and indexed so far.
    private var progress = CarDataProgress(file: nil, lines: [], complete: false)
    private var window: CarDataWindowCache?
    private var windowTask: Task<Void, Never>?
    /// "Speed readouts on mobile data".
    private var allowsExpensive: Bool
    /// The connection is expensive (cellular, a personal hotspot). Unknown (nil) until the
    /// monitor's first answer, when nothing downloads unless mobile data is allowed.
    private var expensive: Bool?
    #if canImport(Network)
    private var monitor: NWPathMonitor?
    #endif

    /// `cacheName`: the session's key (its folder path when F1 gives none), the file's name.
    /// `directory`: where the files go; Caches/cardata unless a test says otherwise.
    init(archive: TimingArchive, sessionPath: String, cacheName: String, streamStart: UTCms, allowsExpensive: Bool,
         directory: URL? = CarDataLoader.defaultDirectory) {
        self.streamStart = streamStart
        self.allowsExpensive = allowsExpensive
        download = CarDataDownload(archive: archive, sessionPath: sessionPath, cacheName: cacheName, directory: directory)
    }

    isolated deinit {
        task?.cancel()
        windowTask?.cancel()
        #if canImport(Network)
        monitor?.cancel()
        #endif
    }

    /// `Caches/cardata/`: the system may clear it; the archive has it all again.
    nonisolated static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("cardata", isDirectory: true)
    }

    /// The file's name for a session: its key, else its folder with anything but letters and
    /// digits made "-".
    nonisolated static func cacheName(key: Int?, path: String) -> String {
        if let key { return String(key) }
        let name = String(path.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" })
        return name.isEmpty ? "session" : name
    }

    /// Starts the download (from the cache, and where a part stopped); does nothing once started.
    func start() {
        guard task == nil else { return }
        startMonitor()
        let download = download
        let allowed: @MainActor @Sendable () -> Bool = { [weak self] in self?.mayDownload ?? false }
        let publish: @MainActor @Sendable (CarDataProgress) -> Void = { [weak self] progress in self?.received(progress) }
        task = Task {
            await download.run(allowed: allowed, publish: publish)
        }
    }

    /// Stops the download and forgets the window (on detach).
    func cancel() {
        task?.cancel()
        task = nil
        windowTask?.cancel()
        windowTask = nil
        window = nil
        #if canImport(Network)
        monitor?.cancel()
        monitor = nil
        #endif
    }

    /// Settings › "Speed readouts on mobile data", followed at once: off pauses before the next piece.
    func setAllowsExpensive(_ on: Bool) {
        allowsExpensive = on
    }

    /// Whether the next piece may download now.
    private var mayDownload: Bool {
        allowsExpensive || expensive == false
    }

    private func startMonitor() {
        #if canImport(Network)
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        // Explicitly @Sendable: it runs on the monitor's queue, never on the main actor.
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let expensive = path.isExpensive
            Task { @MainActor [weak self] in self?.expensive = expensive }
        }
        monitor.start(queue: DispatchQueue(label: "cardata.path", qos: .utility))
        self.monitor = monitor
        #else
        expensive = false
        #endif
    }

    private func received(_ progress: CarDataProgress) {
        self.progress = progress
    }

    // MARK: Samples

    /// Car `car`'s samples around `t` (picture time), oldest first, from the window in memory:
    /// empty until the download has reached `t`. Reading the window again (off the main actor)
    /// starts here when `t` nears its edge or more data has come in for it; until it lands, the
    /// window in hand answers.
    func samples(car: String, around t: UTCms) -> [CarSample] {
        let offset = Self.sub(t, streamStart)
        if progress.file != nil, !progress.lines.isEmpty {
            let wanted = window.map { !$0.covers(offset, margin: Self.windowReloadMarginMs) || $0.grown(progress) } ?? true
            if wanted { reload(around: offset) }
        }
        guard let window, window.offsets.contains(offset) else { return [] }
        return window.cars[car] ?? []
    }

    private func reload(around offset: Int64) {
        guard windowTask == nil, let file = progress.file else { return }
        let lines = progress.lines
        let complete = progress.complete
        let span = Self.windowMs + Self.windowPadMs
        let offsets = Self.sub(offset, span)...Self.add(offset, span)
        windowTask = Task { [weak self] in
            let cars = await Task.detached(priority: .utility) {
                CarDataWindowFile.load(file: file, lines: lines, offsets: offsets)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.window = CarDataWindowCache(
                offsets: offsets, lineCount: lines.count, complete: complete,
                reachesEnd: (lines.last?.offsetMs ?? .min) < offsets.upperBound, cars: cars)
            self.windowTask = nil
        }
    }

    nonisolated static func sub(_ a: Int64, _ b: Int64) -> Int64 {
        let (value, overflow) = a.subtractingReportingOverflow(b)
        return overflow ? (b < 0 ? .max : .min) : value
    }

    nonisolated static func add(_ a: Int64, _ b: Int64) -> Int64 {
        let (value, overflow) = a.addingReportingOverflow(b)
        return overflow ? (b < 0 ? .min : .max) : value
    }
}

/// What the download has on disk: the file being written (the part file until it is whole), its
/// complete lines in order, and whether it is whole.
struct CarDataProgress: Sendable {
    var file: URL?
    var lines: [CarDataLine]
    var complete: Bool
}

/// One complete line of the car data file: its stream offset and where its bytes sit (without
/// the newline).
struct CarDataLine: Sendable, Equatable {
    var offsetMs: Int64
    var start: Int
    var end: Int
}

/// The window in memory.
struct CarDataWindowCache: Sendable {
    var offsets: ClosedRange<Int64>
    /// The lines indexed when it was read.
    var lineCount: Int
    var complete: Bool
    /// The data stopped inside the window when it was read: newer lines may belong in it.
    var reachesEnd: Bool
    var cars: [String: [CarSample]]

    /// `offset` sits inside, at least `margin` from both edges.
    func covers(_ offset: Int64, margin: Int64) -> Bool {
        let lo = CarDataLoader.add(offsets.lowerBound, margin), hi = CarDataLoader.sub(offsets.upperBound, margin)
        return lo <= hi && (lo...hi).contains(offset)
    }

    /// More lines (or the file moving from part to whole) have come in since, for this window.
    func grown(_ progress: CarDataProgress) -> Bool {
        reachesEnd && (progress.lines.count > lineCount || progress.complete != complete)
    }
}

/// Finds the complete lines in the bytes of the car data file. Plain functions.
enum CarDataIndex {
    /// The complete lines in `bytes`, whose first byte sits at `base` in the file, and the file
    /// position just after the last newline (an unfinished last line waits for more bytes). A
    /// UTF-8 BOM at the file's start is skipped; a "\r" before a newline is dropped; a line
    /// that doesn't parse (blank, cut short) is left out.
    static func scan(_ bytes: Data, base: Int) -> (lines: [CarDataLine], next: Int) {
        let buffer = [UInt8](bytes)
        var lines: [CarDataLine] = []
        var lineStart = 0
        for i in buffer.indices where buffer[i] == 0x0A {
            var start = lineStart
            var end = i
            if base + start == 0, end - start >= 3, buffer[start] == 0xEF, buffer[start + 1] == 0xBB, buffer[start + 2] == 0xBF {
                start += 3
            }
            if end > start, buffer[end - 1] == 0x0D { end -= 1 }
            if end > start,
               let line = StreamLine.parse(Substring(String(decoding: buffer[start..<end], as: UTF8.self))) {
                lines.append(CarDataLine(offsetMs: line.offsetMs, start: base + start, end: base + end))
            }
            lineStart = i + 1
        }
        return (lines, base + lineStart)
    }
}

/// Reads one window of lines from the file. Plain functions, for a detached task.
enum CarDataWindowFile {
    /// The samples of the lines whose offset lies in `offsets` (`lines` in file order, which is
    /// time order); empty when the file can't be read.
    static func load(file: URL, lines: [CarDataLine], offsets: ClosedRange<Int64>) -> [String: [CarSample]] {
        var lo = 0, hi = lines.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if lines[mid].offsetMs < offsets.lowerBound { lo = mid + 1 } else { hi = mid }
        }
        var picked: [CarDataLine] = []
        var i = lo
        while i < lines.count, lines[i].offsetMs <= offsets.upperBound {
            picked.append(lines[i])
            i += 1
        }
        guard let first = picked.first, let last = picked.last, last.end > first.start,
              let handle = try? FileHandle(forReadingFrom: file) else { return [:] }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(first.start))) != nil,
              let bytes = try? handle.read(upToCount: last.end - first.start) else { return [:] }
        let buffer = [UInt8](bytes)
        let parsed = picked.compactMap { line -> StreamLine? in
            let a = line.start - first.start, b = line.end - first.start
            guard a >= 0, b <= buffer.count, a < b else { return nil }
            return StreamLine.parse(Substring(String(decoding: buffer[a..<b], as: UTF8.self)))
        }
        return CarDataWindow.parse(lines: parsed)
    }
}

/// The download itself, off the main actor: writes the part file, indexes its lines as they
/// come, and renames it once whole.
actor CarDataDownload {
    private let archive: TimingArchive
    private let sessionPath: String
    private let directory: URL?
    private let chunkBytes: Int
    private let fileURL: URL?
    private let partURL: URL?
    private var lines: [CarDataLine] = []
    /// Bytes on disk.
    private var size = 0
    /// Where the next scan starts, and the bytes from there to `size` (an unfinished line).
    private var scanned = 0
    private var tail = Data()

    init(archive: TimingArchive, sessionPath: String, cacheName: String, directory: URL?,
         chunkBytes: Int = CarDataLoader.chunkBytes) {
        self.archive = archive
        self.sessionPath = sessionPath
        self.directory = directory
        self.chunkBytes = max(chunkBytes, 1)
        fileURL = directory?.appendingPathComponent(cacheName + ".jsonStream")
        partURL = directory?.appendingPathComponent(cacheName + ".jsonStream.part")
    }

    /// Runs until the file is whole, refused or missing, or the task is cancelled. `allowed` is
    /// asked before each piece (false waits); `publish` gets the index after each piece.
    func run(allowed: @escaping @Sendable () async -> Bool,
             publish: @escaping @Sendable (CarDataProgress) async -> Void) async {
        guard let fileURL, let partURL, let directory else { return }
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        Self.deleteOld(in: directory, now: Date())
        if let whole = try? Data(contentsOf: fileURL) {
            append(whole)
            await publish(CarDataProgress(file: fileURL, lines: lines, complete: true))
            return
        }
        if let part = try? Data(contentsOf: partURL) {
            append(part)
            await publish(CarDataProgress(file: partURL, lines: lines, complete: false))
        } else {
            guard manager.createFile(atPath: partURL.path, contents: nil) else { return }
        }
        var attempt = 0
        while !Task.isCancelled {
            while !(await allowed()) {
                guard await Self.sleep(.seconds(5)) else { return }
            }
            let upper = size + chunkBytes - 1
            let answer = await archive.byteRange(sessionPath: sessionPath, name: CarDataLoader.fileName, bytes: size...upper)
            guard !Task.isCancelled else { return }
            switch answer {
            case .partial(let data):
                attempt = 0
                guard !data.isEmpty else { return await finish(publish) }
                guard write(data, to: partURL, replacing: false) else { return }
                append(data)
                if data.count < chunkBytes { return await finish(publish) }
                await publish(CarDataProgress(file: partURL, lines: lines, complete: false))
            case .whole(let data):
                // The range was ignored: this is the whole file. Ranges stop here.
                guard write(data, to: partURL, replacing: true) else { return }
                lines = []
                size = 0
                scanned = 0
                tail = Data()
                append(data)
                return await finish(publish)
            case .unavailable(let status):
                // Past the end of a file already part-written: it is whole. Otherwise refused or
                // missing: no readouts, and nothing to try again.
                if status == 416, size > 0 { return await finish(publish) }
                return
            case .failed:
                let delays = CarDataLoader.retryDelays
                guard await Self.sleep(delays[min(attempt, delays.count - 1)]) else { return }
                attempt += 1
            }
        }
    }

    /// The part file is whole: it becomes the session's file.
    private func finish(_ publish: @Sendable (CarDataProgress) async -> Void) async {
        guard let fileURL, let partURL else { return }
        // Indexes an unfinished last line, should the file not end in a newline.
        if !tail.isEmpty {
            let found = CarDataIndex.scan(tail + Data([0x0A]), base: scanned)
            lines += found.lines
            tail = Data()
        }
        let manager = FileManager.default
        try? manager.removeItem(at: fileURL)
        let done = (try? manager.moveItem(at: partURL, to: fileURL)) != nil
        await publish(CarDataProgress(file: done ? fileURL : partURL, lines: lines, complete: true))
    }

    /// Indexes bytes just added to the file.
    private func append(_ data: Data) {
        size += data.count
        let all = tail + data
        let found = CarDataIndex.scan(all, base: scanned)
        lines += found.lines
        tail = Data(all.dropFirst(found.next - scanned))
        scanned = found.next
    }

    private func write(_ data: Data, to url: URL, replacing: Bool) -> Bool {
        if replacing {
            return (try? data.write(to: url, options: .atomic)) != nil
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return false }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }

    /// Deletes files in `directory` last written more than 7 days before `now`.
    nonisolated static func deleteOld(in directory: URL, now: Date) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        for url in names {
            let written = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let written, now.timeIntervalSince(written) > CarDataLoader.keepFor {
                try? manager.removeItem(at: url)
            }
        }
    }

    /// Waits; false when cancelled.
    private static func sleep(_ duration: Duration) async -> Bool {
        do {
            try await Task.sleep(for: duration)
            return true
        } catch {
            return false
        }
    }
}

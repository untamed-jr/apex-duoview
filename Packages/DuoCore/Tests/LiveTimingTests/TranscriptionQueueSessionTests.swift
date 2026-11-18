import Foundation
import Testing
@testable import LiveTiming

/// The queue's rules end to end: one clip at a time, nearest the picture within two minutes,
/// timeouts skip (and are not failures), three failures wait two minutes, results by path.
/// (`TranscriptionQueueTests` in RadioTests.swift covers the same rules clip by clip; these run
/// them as the app's transcriber loop does, and on the whole race.) Times are wall-clock ms.
@Suite struct TranscriptionQueueSessionTests {
    func clips(_ seconds: Int64...) -> [RadioClip] {
        seconds.map { RadioClip(utc: $0 * 1000, racingNumber: "1", path: "c\($0)") }
    }

    @Test func nearestFirstWithinTwoMinutes() {
        let all = clips(50, 100, 150, 220)
        var queue = TranscriptionQueue()
        var order: [String] = []
        // Picture at 100 s: 100 is nearest; 50 and 150 tie, the earlier first; 220 is exactly 2 minutes ahead.
        while let clip = queue.next(from: all, at: 100_000, now: 0) {
            order.append(clip.path)
            queue.finished(path: clip.path, result: "copy")
        }
        #expect(order == ["c100", "c50", "c150", "c220"])
    }

    @Test func nothingBeyondTwoMinutes() {
        var queue = TranscriptionQueue()
        #expect(queue.next(from: clips(221), at: 100_000, now: 0) == nil)
        #expect(TranscriptionQueue.aheadMs == 120_000)
        // 120.000 s ahead is in, and a millisecond more is out.
        #expect(queue.next(from: [RadioClip(utc: 220_001, racingNumber: "1", path: "x")], at: 100_000, now: 0) == nil)
        #expect(queue.next(from: [RadioClip(utc: 220_000, racingNumber: "1", path: "y")], at: 100_000, now: 0)?.path == "y")
    }

    @Test func oneAtATime() {
        let all = clips(100, 101, 102)
        var queue = TranscriptionQueue()
        #expect(queue.next(from: all, at: 100_000, now: 0)?.path == "c100")
        for now in stride(from: Int64(0), to: 45_000, by: 5_000) {
            #expect(queue.next(from: all, at: 100_000, now: now) == nil)
        }
        queue.finished(path: "c100", result: "box")
        #expect(queue.next(from: all, at: 100_000, now: 1_000)?.path == "c101")
    }

    @Test func queueTimeoutSkips() {
        let all = clips(100, 110)
        var queue = TranscriptionQueue()
        #expect(queue.next(from: all, at: 100_000, now: 0)?.path == "c100")
        queue.timedOut(path: "c100")
        // Never offered again before a wait, however often and however late it asks.
        var offered: [String] = []
        if let clip = queue.next(from: all, at: 100_000, now: 1_000) {
            offered.append(clip.path)
            queue.finished(path: clip.path, result: "words")
        }
        for now in stride(from: Int64(2_000), to: 600_000, by: 30_000) {
            if let clip = queue.next(from: all, at: 100_000, now: now) { offered.append(clip.path) }
        }
        #expect(offered == ["c110"])
        // Android's rules: a timeout is not a failure, so it never starts the wait on its own.
        #expect(queue.failuresInRow == 0)
        #expect(queue.waitingUntil == nil)
        // The wait after three failures forgives skipped clips (the timed-out one included).
        var later = TranscriptionQueue()
        let more = clips(100, 110, 120, 130)
        #expect(later.next(from: more, at: 100_000, now: 0)?.path == "c100")
        later.timedOut(path: "c100")
        for (i, path) in ["c110", "c120", "c130"].enumerated() {
            #expect(later.next(from: more, at: 100_000, now: 0)?.path == path, "\(i)")
            later.failed(path: path, at: 5_000)
        }
        #expect(later.next(from: more, at: 100_000, now: 124_999) == nil)
        #expect(later.next(from: more, at: 100_000, now: 125_000)?.path == "c100")
    }

    @Test func threeFailuresWaitTwoMinutes() {
        let all = clips(100, 101, 102, 103)
        var queue = TranscriptionQueue()
        let failedAt: Int64 = 10_000
        for path in ["c100", "c101", "c102"] {
            #expect(queue.next(from: all, at: 100_000, now: failedAt)?.path == path)
            queue.failed(path: path, at: failedAt)
        }
        // Nothing at +119 s, a clip at +120 s.
        #expect(queue.next(from: all, at: 100_000, now: failedAt + 119_000) == nil)
        #expect(queue.next(from: all, at: 100_000, now: failedAt + 119_999) == nil)
        #expect(queue.next(from: all, at: 100_000, now: failedAt + 120_000)?.path == "c100")
        queue.finished(path: "c100", result: "copy")

        // A success resets the count: two failures, a success, two more failures is no wait.
        var fresh = TranscriptionQueue()
        let many = clips(1, 2, 3, 4, 5, 6)
        for path in ["c1", "c2"] {
            #expect(fresh.next(from: many, at: 0, now: 0)?.path == path)
            fresh.failed(path: path, at: 0)
        }
        #expect(fresh.next(from: many, at: 0, now: 0)?.path == "c3")
        fresh.finished(path: "c3", result: "ok")
        for path in ["c4", "c5"] {
            #expect(fresh.next(from: many, at: 0, now: 0)?.path == path)
            fresh.failed(path: path, at: 0)
        }
        #expect(fresh.waitingUntil == nil)
        #expect(fresh.next(from: many, at: 0, now: 0)?.path == "c6")
    }

    @Test func noWordsStored() {
        let all = clips(100)
        var queue = TranscriptionQueue()
        _ = queue.next(from: all, at: 100_000, now: 0)
        queue.finished(path: "c100", result: " \n ")
        #expect(queue.results["c100"] == "(no words recognised)")
        #expect(queue.transcript(for: all[0], at: 100_000) == TranscriptionQueue.noWords)
        // A result is a result: it is not offered again, and it is hidden before picture time reaches it.
        #expect(queue.next(from: all, at: 100_000, now: 0) == nil)
        #expect(queue.transcript(for: all[0], at: 99_999) == nil)
    }

    @Test func resultsKeyedByPath() {
        var queue = TranscriptionQueue(results: ["c100": "kept from before"])
        let all = clips(100, 105)
        #expect(queue.next(from: all, at: 100_000, now: 0)?.path == "c105")
        // The same path in a clip with another time (a re-published list) is the same clip.
        let moved = [RadioClip(utc: 100_000, racingNumber: "9", path: "c100")]
        queue.finished(path: "c105", result: "next")
        #expect(queue.next(from: moved, at: 100_000, now: 0) == nil)
        #expect(queue.transcript(for: moved[0], at: 100_000) == "kept from before")
    }

    @Test func wholeRaceModeOldestFirst() throws {
        let radio = try RadioRaceTests.raceRadio()
        var queue = TranscriptionQueue()
        var order: [String] = []
        // No picture time: every clip is due, no 2-minute limit, oldest first, one at a time.
        while let clip = queue.next(from: radio.all, at: nil, now: 0) {
            #expect(queue.next(from: radio.all, at: nil, now: 1_000) == nil)
            order.append(clip.path)
            queue.finished(path: clip.path, result: "x")
        }
        #expect(order == radio.all.map(\.path))
        #expect(order.count == 30)
    }
}

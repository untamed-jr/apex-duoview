import Foundation
import Testing
import F1TV
@testable import LiveTiming

/// `LiveFeed.session()` folds only the lines added since its last call into the timelines it
/// keeps; the session it returns is the one a fresh feed, given the same messages and top-ups,
/// builds from scratch.
struct LiveFeedFoldTests {
    enum Step {
        case message(RecordedMessage)
        case topUp([String: [StreamLine]], UTCms)
    }

    /// A fresh feed given `steps`, asked once.
    func fresh(_ steps: [Step]) -> LoadedSession? {
        var feed = LiveFeed()
        for step in steps {
            switch step {
            case .message(let m): feed.apply(m)
            case .topUp(let archive, let start): feed.topUp(archive: archive, archiveStart: start)
            }
        }
        return feed.session()
    }

    /// Every timeline of the two sessions, whole.
    func expectIdentical(_ a: LoadedSession?, _ b: LoadedSession?, _ label: String,
                         sourceLocation: SourceLocation = #_sourceLocation) {
        guard let a, let b else {
            #expect(a == nil && b == nil, "\(label): one is nil", sourceLocation: sourceLocation)
            return
        }
        #expect(a.streamStart == b.streamStart, "\(label) stream start", sourceLocation: sourceLocation)
        #expect(a.info == b.info, "\(label) info", sourceLocation: sourceLocation)
        #expect(a.drivers == b.drivers, "\(label) drivers", sourceLocation: sourceLocation)
        #expect(a.missing == b.missing, "\(label) missing", sourceLocation: sourceLocation)
        #expect(a.sessionStatus == b.sessionStatus, "\(label) status", sourceLocation: sourceLocation)
        // Positions: every sample of every car.
        #expect(Set(a.positions.cars.keys) == Set(b.positions.cars.keys), "\(label) cars", sourceLocation: sourceLocation)
        for (number, car) in b.positions.cars {
            guard let mine = a.positions.cars[number] else { continue }
            #expect(mine.times == car.times, "\(label) car \(number) times", sourceLocation: sourceLocation)
            if mine.times == car.times {
                #expect(mine.times.indices.allSatisfy { mine.point($0) == car.point($0) }, "\(label) car \(number) points",
                        sourceLocation: sourceLocation)
            }
        }
        // Timing: every state, update, part and finished lap.
        #expect(a.timing.updateTimes == b.timing.updateTimes, "\(label) updates", sourceLocation: sourceLocation)
        #expect(a.timing.partTimes == b.timing.partTimes && a.timing.parts == b.timing.parts, "\(label) parts",
                sourceLocation: sourceLocation)
        #expect(a.timing.cars.mapValues(\.times) == b.timing.cars.mapValues(\.times), "\(label) timing times",
                sourceLocation: sourceLocation)
        #expect(a.timing.cars.mapValues(\.states) == b.timing.cars.mapValues(\.states), "\(label) timing states",
                sourceLocation: sourceLocation)
        #expect(a.timing.completed.mapValues(\.times) == b.timing.completed.mapValues(\.times), "\(label) lap times",
                sourceLocation: sourceLocation)
        #expect(a.timing.completed.mapValues(\.laps) == b.timing.completed.mapValues(\.laps), "\(label) laps",
                sourceLocation: sourceLocation)
        #expect(a.stints.cars.mapValues(\.times) == b.stints.cars.mapValues(\.times), "\(label) stint times",
                sourceLocation: sourceLocation)
        #expect(a.stints.cars.mapValues(\.stints) == b.stints.cars.mapValues(\.stints), "\(label) stints",
                sourceLocation: sourceLocation)
        #expect(a.header.lapTimes == b.header.lapTimes && a.header.laps == b.header.laps
                && a.header.totalTimes == b.header.totalTimes && a.header.totals == b.header.totals
                && a.header.marks == b.header.marks && a.header.weather == b.header.weather
                && a.header.weatherTimes == b.header.weatherTimes, "\(label) header", sourceLocation: sourceLocation)
        #expect(a.flags.spans == b.flags.spans && a.flags.statusTimes == b.flags.statusTimes
                && a.flags.statusCodes == b.flags.statusCodes && a.flags.sectorFlags.count == b.flags.sectorFlags.count,
                "\(label) flags", sourceLocation: sourceLocation)
    }

    @Test func incrementalSessionIsTheFreshOne() async throws {
        let replay = try ArchiveReplay()
        let changes = replay.changes
        var steps: [Step] = []
        var feed = LiveFeed()
        func apply(_ messages: some Sequence<RecordedMessage>) {
            for m in messages {
                feed.apply(m)
                steps.append(.message(m))
            }
        }
        func topUp(_ archive: [String: [StreamLine]]) {
            feed.topUp(archive: archive, archiveStart: replay.start)
            steps.append(.topUp(archive, replay.start))
        }

        // Halfway through the first snapshot (DriverList, SessionInfo, Position, TimingData, ...).
        apply(replay.opening.prefix(4))
        expectIdentical(feed.session(), fresh(steps), "mid snapshot")
        apply(replay.opening.dropFirst(4))
        expectIdentical(feed.session(), fresh(steps), "snapshot")

        // Changes, asked at several points.
        let reconnect = Self.lightsOut + 180_000
        let k = try #require(changes.firstIndex { $0.utc > reconnect })
        for cut in [k / 5, k / 3, k / 2, k - 7, k - 6] {
            apply(changes[steps.count - replay.opening.count..<cut])
            expectIdentical(feed.session(), fresh(steps), "change \(cut)")
        }
        apply(changes[(steps.count - replay.opening.count)..<k])
        _ = feed.session()

        // A reconnect: its snapshot, then changes.
        apply(replay.snapshot(at: reconnect, through: reconnect))
        expectIdentical(feed.session(), fresh(steps), "reconnect snapshot")
        let more = changes[k...].prefix(1_500)
        apply(more.prefix(700))
        expectIdentical(feed.session(), fresh(steps), "after the reconnect")

        // A lagging top-up, then a fuller one, with changes between.
        topUp(replay.streams.mapValues { $0.filter { replay.utc($0) <= Self.lightsOut - 600_000 } })
        expectIdentical(feed.session(), fresh(steps), "lagging top-up")
        apply(more.dropFirst(700).prefix(400))
        expectIdentical(feed.session(), fresh(steps), "after the lagging top-up")
        topUp(replay.streams)
        expectIdentical(feed.session(), fresh(steps), "full top-up")
        apply(more.dropFirst(1_100))
        expectIdentical(feed.session(), fresh(steps), "after the full top-up")

        // Nothing new: the same session.
        expectIdentical(feed.session(), fresh(steps), "asked again")

        // Another session: the feed starts afresh from its snapshot.
        var info = replay.sessionInfo
        if case .object(var members) = info {
            members["Path"] = .string("2026/next/")
            info = .object(members)
        }
        let next = try #require(changes.last).utc + 60_000
        apply([RecordedMessage(topic: "SessionInfo", utc: next, opening: true, json: info),
               RecordedMessage(topic: "LapCount", utc: next, opening: true, json: .object(["CurrentLap": .number(1)]))])
        let renewed = feed.session()
        expectIdentical(renewed, fresh(steps), "new session")
        #expect(renewed?.info.path == "2026/next/")
    }

    @Test func eachLineIsFoldedOnce() throws {
        let replay = try ArchiveReplay()
        let changes = replay.changes
        var feed = LiveFeed()
        for m in replay.opening + changes.prefix(2_000) { feed.apply(m) }
        let first = feed.session()
        for m in changes.dropFirst(2_000).prefix(300) { feed.apply(m) }
        let second = feed.session()
        let third = feed.session()
        #expect(first != nil && second != nil && third != nil)
        // Since the feed began, every line was read once, not once per call.
        for topic in LiveFeed.foldedTopics {
            #expect(feed.folded(topic) == feed.lines(topic).count, "\(topic)")
        }
        #expect(feed.folded("Position.z") > 0)

        // A top-up puts other lines first: those are read again, once.
        feed.topUp(archive: replay.streams, archiveStart: replay.start)
        let topped = feed.session()
        for m in changes.dropFirst(2_300).prefix(50) { feed.apply(m) }
        let after = feed.session()
        #expect(topped != nil && after != nil)
        for topic in LiveFeed.foldedTopics {
            #expect(feed.folded(topic) == feed.lines(topic).count, "\(topic) after the top-up")
        }
    }

    static let lightsOut = Fixture.raceLightsOut
}

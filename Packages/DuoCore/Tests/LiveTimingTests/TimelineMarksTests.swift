import Foundation
import Testing
import F1TV
@testable import LiveTiming

/// The timeline's marks: lights out and the chequered flag always; flag periods only up to
/// picture time unless the whole race is asked for.
@Suite struct TimelineMarksTests {
    static let playerSeconds = 1_000.0

    static func quali() async throws -> LoadedSession {
        let http = FakeArchiveHTTP()
        try await http.serveSession(fixture: "sp26-quali", at: TimingArchiveTests.qualiPath)
        return try #require(await TimingArchive.load(TimingArchiveTests.quali, using: TimingArchiveTests.archive(http)))
    }

    /// The race window with a safety car added from 5 min after lights out (00:58:44.576) to
    /// 01:02:00.000, and the chequered flag at 01:04:00.000.
    static let scStart = Fixture.raceStart + 3_524_576
    static let scEnd = Fixture.raceStart + 3_720_000
    static let finished = Fixture.raceStart + 3_840_000

    static func raceWithSafetyCar() async throws -> LoadedSession {
        let http = try await TimingArchiveTests.raceHTTP()
        let path = TimingArchiveTests.racePath
        var track = try Fixture.data("sp26-race/TrackStatus.jsonStream")
        track.append(Data("00:58:44.576{\"Status\":\"4\",\"Message\":\"SCDeployed\"}\n01:02:00.000{\"Status\":\"1\",\"Message\":\"AllClear\"}\n".utf8))
        await http.serve(path + "TrackStatus.jsonStream", body: track)
        var status = try Fixture.data("sp26-race/SessionStatus.jsonStream")
        status.append(Data("01:04:00.000{\"Status\":\"Finished\",\"Started\":\"Finished\"}\n".utf8))
        await http.serve(path + "SessionStatus.jsonStream", body: status)
        return try #require(await TimingArchive.load(TimingArchiveTests.race, using: TimingArchiveTests.archive(http)))
    }

    static func bands(_ marks: [TimelineMark]) -> [(kind: FlagSpan.Kind, from: Double, to: Double)] {
        marks.compactMap { if case .band(let k, let f, let t) = $0 { return (k, f, t) }; return nil }
    }

    static func second(_ u: UTCms, at picture: UTCms) -> Double {
        ((playerSeconds + (Double(u) - Double(picture)) / 1000) * 10).rounded() / 10
    }

    @Test func qualifyingRedFlagIsCutAtPictureTime() async throws {
        let session = try await Self.quali()
        let red = try #require(session.flags.spans.first { $0.kind == .red })
        // Before it: no band at all, but the session's start is there.
        let before = TimelineMark.marks(for: session, pictureTime: red.start - 1, playerSeconds: Self.playerSeconds, wholeRace: false)
        #expect(Self.bands(before).isEmpty)
        #expect(before.contains(.lightsOut(at: Self.second(Fixture.qualiQ1, at: red.start - 1), label: "Session start")))
        // A minute in, still out: the band runs from its start to picture time, no further.
        let picture = red.start + 60_000
        let marks = TimelineMark.marks(for: session, pictureTime: picture, playerSeconds: Self.playerSeconds, wholeRace: false)
        let bands = Self.bands(marks)
        #expect(bands.count == 1)
        #expect(bands.first?.kind == .red)
        #expect(bands.first?.from == Self.playerSeconds - 60)
        #expect(bands.first?.to == Self.playerSeconds)
        // Nothing after picture time.
        #expect(bands.allSatisfy { $0.to <= Self.playerSeconds })
        #expect(marks.contains(.lightsOut(at: Self.second(Fixture.qualiQ1, at: picture), label: "Session start")))
    }

    @Test func wholeRaceShowsEveryPeriodInFull() async throws {
        let session = try await Self.quali()
        let red = try #require(session.flags.spans.first { $0.kind == .red })
        let marks = TimelineMark.marks(for: session, pictureTime: Fixture.qualiQ1, playerSeconds: Self.playerSeconds, wholeRace: true)
        let full = try #require(Self.bands(marks).first { $0.kind == .red })
        #expect(full.from == Self.second(red.start, at: Fixture.qualiQ1))
        #expect(full.to == (red.end.map { Self.second($0, at: Fixture.qualiQ1) } ?? .infinity))
        #expect(Self.bands(marks).count == session.flags.spans.count)
    }

    @Test func safetyCarShowsOnlyAsFarAsThePicture() async throws {
        let session = try await Self.raceWithSafetyCar()
        let sc = try #require(session.flags.spans.first { $0.kind == .safetyCar })
        #expect(sc.start == Self.scStart)
        #expect(sc.end == Self.scEnd)

        // At lights out: no band yet; lights out and the chequered flag both show.
        let early = TimelineMark.marks(for: session, pictureTime: Fixture.raceLightsOut, playerSeconds: Self.playerSeconds, wholeRace: false)
        #expect(Self.bands(early).isEmpty)
        #expect(early.contains(.lightsOut(at: Self.playerSeconds, label: "Lights out")))
        #expect(early.contains(.chequered(at: Self.second(Self.finished, at: Fixture.raceLightsOut))))

        // During it: cut at picture time.
        let during = Self.scStart + 30_000
        let mid = Self.bands(TimelineMark.marks(for: session, pictureTime: during, playerSeconds: Self.playerSeconds, wholeRace: false))
        #expect(mid.count == 1)
        #expect(mid.first?.kind == .safetyCar)
        #expect(mid.first?.from == Self.playerSeconds - 30)
        #expect(mid.first?.to == Self.playerSeconds)

        // After it: the whole period, which ends before picture time.
        let after = Self.scEnd + 10_000
        let done = Self.bands(TimelineMark.marks(for: session, pictureTime: after, playerSeconds: Self.playerSeconds, wholeRace: false))
        #expect(done.count == 1)
        #expect(done.first?.from == Self.second(Self.scStart, at: after))
        #expect(done.first?.to == Self.playerSeconds - 10)

        // The whole race: the period in full, even from lights out.
        let whole = Self.bands(TimelineMark.marks(for: session, pictureTime: Fixture.raceLightsOut, playerSeconds: Self.playerSeconds, wholeRace: true))
        #expect(whole.count == 1)
        #expect(whole.first?.to == Self.second(Self.scEnd, at: Fixture.raceLightsOut))
    }

    @Test func clippingAndLabels() {
        #expect(TimelineMark.band(.vsc, from: -5, to: .infinity).clipped(to: 0...100) == .band(.vsc, from: 0, to: 100))
        #expect(TimelineMark.chequered(at: 101).clipped(to: 0...100) == nil)
        #expect(TimelineMark.band(.red, from: 120, to: 130).clipped(to: 0...100) == nil)
        #expect(TimelineMark.lightsOut(at: 3, label: "Lights out").label == "Lights out")
        #expect(TimelineMark.band(.safetyCar, from: 0, to: 1).label == "Safety car")
    }

    @Test func noPlayerTimeNoMarks() async throws {
        let session = try await Self.quali()
        #expect(TimelineMark.marks(for: session, pictureTime: Fixture.qualiQ1, playerSeconds: .nan, wholeRace: true).isEmpty)
    }
}

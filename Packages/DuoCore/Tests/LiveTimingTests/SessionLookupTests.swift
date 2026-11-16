import Foundation
import Testing
import F1TV
@testable import LiveTiming

/// Finding the archive session for an F1 TV video: by session key, by meeting and session name,
/// or for a live moment by the weekend's session that had started.
@Suite struct SessionLookupTests {
    static let index = try! Fixture.json("Index-2026.json")
    static let saoPaulo = "2026/2026-11-08_São_Paulo_Grand_Prix/"
    // Interlagos is GMT−3: the race starts 14:00 local, 17:00 UTC; qualifying 15:00 local the day before.
    static let raceStart = SignalR.utc("2026-11-08T17:00:00Z")!
    static let qualiStart = SignalR.utc("2026-11-07T18:00:00Z")!

    static func ref(meetingKey: String = "1299", sessionKey: String? = nil, meetingName: String = "São Paulo Grand Prix",
                    title: String, start: Date? = nil) -> TimingRef {
        TimingRef(year: 2026, meetingKey: meetingKey, sessionKey: sessionKey, circuitKey: 14,
                  meetingName: meetingName, title: title, start: start)
    }

    @Test func matchBySessionKey() throws {
        let found = try #require(SessionLookup.match(index: Self.index, ref: Self.ref(sessionKey: "11408", title: "Anything"), watched: nil))
        #expect(found == ArchiveSession(key: 11408, name: "Qualifying", type: "Qualifying",
                                        path: Self.saoPaulo + "2026-11-07_Qualifying/", start: Self.qualiStart,
                                        gmtOffsetSeconds: -10_800))
        // The key wins over the title and over a meeting key that disagrees.
        let race = SessionLookup.match(index: Self.index, ref: Self.ref(meetingKey: "1", sessionKey: "11412", title: "Practice 1"), watched: nil)
        #expect(race?.name == "Race")
        #expect(race?.start == Self.raceStart)
    }

    @Test func matchByMeetingAndLongestName() throws {
        // "Sprint Qualifying" contains "Qualifying"; the longest name in the title wins, in any case.
        let sprintWeekend = try JSONValue.parse(Data("""
        {"Year":2026,"Meetings":[
          {"Key":1280,"Name":"Chinese Grand Prix","Sessions":[
            {"Key":1,"Type":"Practice","Name":"Practice 1","StartDate":"2026-03-13T11:30:00","GmtOffset":"08:00:00","Path":"2026/2026-03-15_Chinese_Grand_Prix/2026-03-13_Practice_1/"},
            {"Key":2,"Type":"Qualifying","Name":"Sprint Qualifying","StartDate":"2026-03-13T15:30:00","GmtOffset":"08:00:00","Path":"2026/2026-03-15_Chinese_Grand_Prix/2026-03-13_Sprint_Qualifying/"},
            {"Key":3,"Type":"Race","Name":"Sprint","StartDate":"2026-03-14T11:00:00","GmtOffset":"08:00:00","Path":"2026/2026-03-15_Chinese_Grand_Prix/2026-03-14_Sprint/"},
            {"Key":4,"Type":"Qualifying","Name":"Qualifying","StartDate":"2026-03-14T15:00:00","GmtOffset":"08:00:00","Path":"2026/2026-03-15_Chinese_Grand_Prix/2026-03-14_Qualifying/"},
            {"Key":5,"Type":"Race","Name":"Race","StartDate":"2026-03-15T15:00:00","GmtOffset":"08:00:00","Path":"2026/2026-03-15_Chinese_Grand_Prix/2026-03-15_Race/"}]},
          {"Key":1281,"Name":"Japanese Grand Prix","Sessions":[
            {"Key":6,"Type":"Qualifying","Name":"GP - Sprint Qualifying","StartDate":"2026-03-27T15:00:00","GmtOffset":"09:00:00","Path":"2026/2026-03-29_Japanese_Grand_Prix/2026-03-27_X/"}]}
        ]}
        """.utf8))
        func ref(_ title: String, meetingKey: String = "1280") -> TimingRef {
            TimingRef(year: 2026, meetingKey: meetingKey, meetingName: "Chinese Grand Prix", title: title)
        }
        #expect(SessionLookup.match(index: sprintWeekend, ref: ref("2026 Chinese GP - Sprint Qualifying"), watched: nil)?.key == 2)
        #expect(SessionLookup.match(index: sprintWeekend, ref: ref("2026 CHINESE GP - QUALIFYING"), watched: nil)?.key == 4)
        #expect(SessionLookup.match(index: sprintWeekend, ref: ref("2026 Chinese GP - Sprint"), watched: nil)?.key == 3)
        // The meeting by name when its key is unknown.
        #expect(SessionLookup.match(index: sprintWeekend, ref: ref("2026 Chinese GP - Practice 1", meetingKey: ""), watched: nil)?.key == 1)
        // Fixture index: "2026 São Paulo GP - Practice 2".
        let p2 = SessionLookup.match(index: Self.index, ref: Self.ref(title: "2026 São Paulo GP - Practice 2"), watched: nil)
        #expect(p2?.path == Self.saoPaulo + "2026-11-06_Practice_2/")
        // Another meeting's session never matches by name.
        #expect(SessionLookup.match(index: Self.index, ref: Self.ref(meetingKey: "1300", meetingName: "Las Vegas Grand Prix", title: "Race"), watched: nil) == nil)
    }

    @Test func matchLiveByStartWindow() {
        // A live broadcast's title names only the event.
        let live = Self.ref(title: "São Paulo Grand Prix")
        func at(_ t: UTCms) -> ArchiveSession? { SessionLookup.match(index: Self.index, ref: live, watched: t) }
        #expect(at(Self.raceStart + 3_600_000)?.name == "Race")
        #expect(at(Self.raceStart + 4 * 3_600_000 - 1)?.name == "Race")
        #expect(at(Self.raceStart + 4 * 3_600_000) == nil)
        // Android's 30 min before a start: the build-up on the live channel.
        #expect(at(Self.raceStart - 30 * 60_000)?.name == "Race")
        #expect(at(Self.raceStart - 30 * 60_000 - 1) == nil)
        // The latest session that had started: at qualifying, not practice 3 that morning.
        #expect(at(Self.qualiStart + 60_000)?.name == "Qualifying")
        #expect(at(Self.qualiStart - 3 * 3_600_000 + 60_000)?.name == "Practice 3")
        // A name in the title still comes first.
        #expect(SessionLookup.match(index: Self.index, ref: Self.ref(title: "Practice 1"), watched: Self.raceStart)?.name == "Practice 1")
    }

    @Test func noMatchReturnsNil() throws {
        #expect(SessionLookup.match(index: Self.index, ref: Self.ref(title: "São Paulo Grand Prix"), watched: nil) == nil)
        #expect(SessionLookup.match(index: Self.index, ref: Self.ref(sessionKey: "11408001", title: "Pre-Show"), watched: nil) == nil)
        #expect(SessionLookup.match(index: .null, ref: Self.ref(sessionKey: "11408", title: "Qualifying"), watched: nil) == nil)
        // An empty key or name in the reference can't match an index entry that has none.
        let keyless = try JSONValue.parse(Data(#"{"Meetings":[{"Sessions":[{"Key":9,"Type":"Race","Name":"Race","StartDate":"2026-11-08T14:00:00","GmtOffset":"-03:00:00","Path":"2026/x/2026-11-08_Race/"}]}]}"#.utf8))
        #expect(SessionLookup.match(index: keyless, ref: Self.ref(meetingKey: "", meetingName: "", title: "Race"), watched: nil) == nil)
    }

    @Test func probePathsFollowTheTitleAndTheDay() {
        // A titled session: only its folder, on the day of the watched moment at the track.
        let p2 = SessionLookup.probePaths(ref: Self.ref(title: "2026 São Paulo GP - Practice 2"), meetingFolder: Self.saoPaulo,
                                          gmtOffsetSeconds: -10_800, watched: SignalR.utc("2026-11-07T01:30:00Z"))
        #expect(p2 == [Self.saoPaulo + "2026-11-06_Practice_2/"])
        // A live title names no session: every folder F1 uses, for that day.
        let live = SessionLookup.probePaths(ref: Self.ref(title: "São Paulo Grand Prix"), meetingFolder: Self.saoPaulo,
                                            gmtOffsetSeconds: -10_800, watched: Self.raceStart)
        #expect(live.count == 8)
        #expect(live.allSatisfy { $0.hasPrefix(Self.saoPaulo + "2026-11-08_") && $0.hasSuffix("/") })
        #expect(live.contains(Self.saoPaulo + "2026-11-08_Race/"))
        #expect(live.contains(Self.saoPaulo + "2026-11-08_Sprint_Qualifying/"))
        // From the brief's two arguments: the session's start, with no offset known, may be either
        // side of midnight at the track.
        let byStart = SessionLookup.probePaths(ref: Self.ref(title: "2026 São Paulo GP - Qualifying",
                                                             start: Date(timeIntervalSince1970: Double(Self.qualiStart) / 1000)),
                                               meetingFolder: Self.saoPaulo)
        #expect(byStart.contains(Self.saoPaulo + "2026-11-07_Qualifying/"))
        #expect(byStart.count <= 3)
        #expect(!byStart.contains { $0.contains("Sprint") })
        // Nothing to date it by: the weekend's three days, from the meeting's folder name.
        let undated = SessionLookup.probePaths(ref: Self.ref(title: "2026 São Paulo GP - Race"), meetingFolder: String(Self.saoPaulo.dropLast()))
        #expect(Set(undated) == [Self.saoPaulo + "2026-11-06_Race/", Self.saoPaulo + "2026-11-07_Race/", Self.saoPaulo + "2026-11-08_Race/"])
        #expect(SessionLookup.probePaths(ref: Self.ref(title: "Race"), meetingFolder: "2026/no-date/").isEmpty)
    }
}

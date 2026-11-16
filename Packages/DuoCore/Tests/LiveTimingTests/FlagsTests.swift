import Testing
import Foundation
import F1TV
@testable import LiveTiming

/// Ported from Android's FlagsTest (origin/og-android app/src/test/java/app/apexview/FlagsTest.kt).
@Suite struct FlagsTests {
    static func utc(_ iso: String) -> UTCms { SignalR.utc(iso)! }

    static let t0 = utc("2026-10-25T20:00:00Z")
    static func us(_ hms: String) -> UTCms { utc("2026-10-25T\(hms)Z") }

    // As the 2026 US GP sent them: a double yellow and a yellow behind it, cleared one by one,
    // then a VSC that ends with "TRACK CLEAR".
    static let rc = lines(
        #"00:04:42.000{"Messages":[{"Utc":"2026-10-25T20:04:42","Category":"Flag","Flag":"DOUBLE YELLOW","Scope":"Sector","Sector":2,"Message":"DOUBLE YELLOW IN TRACK SECTOR 2"},{"Utc":"2026-10-25T20:04:42","Category":"Flag","Flag":"YELLOW","Scope":"Sector","Sector":1,"Message":"YELLOW IN TRACK SECTOR 1"}]}"#,
        #"00:04:53.000{"Messages":{"7":{"Utc":"2026-10-25T20:04:53","Category":"Flag","Flag":"CLEAR","Scope":"Sector","Sector":2,"Message":"CLEAR IN TRACK SECTOR 2"}}}"#,
        #"00:05:43.000{"Messages":{"9":{"Utc":"2026-10-25T20:05:43","Category":"Flag","Flag":"YELLOW","Scope":"Sector","Sector":9,"Message":"YELLOW IN TRACK SECTOR 9"}}}"#,
        #"00:05:50.000{"Messages":{"10":{"Utc":"2026-10-25T20:05:50","Category":"Other","Message":"OVERTAKE DISABLED"}}}"#,
        #"00:06:30.000{"Messages":{"12":{"Utc":"2026-10-25T20:06:30","Category":"Flag","Flag":"CLEAR","Scope":"Track","Message":"TRACK CLEAR"}}}"#
    )

    static let status = lines(
        #"00:06:06.000{"Status":"6","Message":"VSCDeployed"}"#,
        #"00:06:20.000{"Status":"7","Message":"VSCEnding"}"#,
        #"00:06:30.000{"Status":"1","Message":"AllClear"}"#
    )

    static let flags = TrackFlags.build(trackStatus: status, raceControl: rc, streamStart: t0, gmtOffsetSeconds: -18000)

    @Test func flagsSectorYellowLevel2() {
        let first = Self.flags.at(Self.us("20:04:45"))
        #expect(first.status == .clear)
        #expect(first.yellowSectors == [2: 2, 1: 1])
        #expect(first.caption == nil)
        // Sector 2 cleared on its own; sector 1 stays yellow until race control clears the track.
        #expect(Self.flags.at(Self.us("20:05:00")).yellowSectors == [1: 1])
        #expect(Self.flags.at(Self.us("20:05:45")).yellowSectors == [1: 1, 9: 1])
        #expect(Self.flags.at(Self.us("20:06:31")).yellowSectors.isEmpty)
        #expect(Self.flags.at(Self.us("20:04:41")).yellowSectors.isEmpty)
    }

    @Test func flagsVscEnding() {
        #expect(Self.flags.at(Self.us("20:06:00")).status == .clear)
        #expect(Self.flags.at(Self.us("20:06:10")).status == .vsc)
        #expect(Self.flags.at(Self.us("20:06:10")).caption == "Virtual safety car")
        #expect(Self.flags.at(Self.us("20:06:25")).status == .vscEnding)
        #expect(Self.flags.at(Self.us("20:06:25")).caption == "VSC ending")
        #expect(Self.flags.at(Self.us("20:06:31")).status == .clear)
        #expect(Self.flags.spans == [FlagSpan(kind: .vsc, start: Self.us("20:06:06"), end: Self.us("20:06:30"))])
        let red = TrackFlags.build(trackStatus: lines(#"00:00:00.000{"Status":"5"}"#), raceControl: [], streamStart: Self.t0, gmtOffsetSeconds: 0)
        #expect(red.at(Self.t0 + 1).status == .red)
        #expect(red.spans == [FlagSpan(kind: .red, start: Self.t0, end: nil)])
    }

    @Test func flagsRedCountdown() throws {
        // 2026 Belgian GP qualifying: red at 14:56:55 UTC, "Q3 WILL RESUME AT 17:04" (local, GMT+2).
        let spa = Self.utc("2026-07-18T14:00:00Z")
        let rc = lines(
            #"00:56:55.000{"Messages":[{"Utc":"2026-07-18T14:56:55","Category":"Flag","Flag":"RED","Scope":"Track","Message":"RED FLAG"}]}"#,
            #"01:00:16.000{"Messages":{"30":{"Utc":"2026-07-18T15:00:16","Category":"Other","Message":"Q3 WILL RESUME AT 17:04"}}}"#
        )
        let flags = TrackFlags.build(trackStatus: lines(#"00:56:55.000{"Status":"5","Message":"Red"}"#), raceControl: rc,
                                     streamStart: spa, gmtOffsetSeconds: 7200)
        let at = Self.utc("2026-07-18T15:00:30Z")
        #expect(flags.at(at).caption == "Red flag · Q3 resumes in 3:30")
        #expect(flags.at(at).resumesAt == Self.utc("2026-07-18T15:04:00Z"))
        // Before it's announced there's no countdown; after the time, none either.
        #expect(flags.at(Self.utc("2026-07-18T14:58:00Z")).caption == "Red flag")
        #expect(flags.at(Self.utc("2026-07-18T15:04:00Z")).resumesAt == nil)
        // "ESTIMATED TIME OF SQ1 RESUMPTION - 16:59" at GMT−4.
        let estimated = try #require(TrackFlags.resumption("ESTIMATED TIME OF SQ1 RESUMPTION - 16:59",
                                                           said: Self.utc("2026-05-22T20:54:38Z"), offset: -14400))
        #expect(estimated.what == "SQ1 resumes")
        #expect(estimated.at == Self.utc("2026-05-22T20:59:00Z"))
        #expect(TrackFlags.resumption("RACE WILL RESTART AT 15:42", said: Self.utc("2026-07-19T13:30:00Z"), offset: 7200)?.what == "Race restarts")
        #expect(TrackFlags.resumption("Q2 WILL NOT BE RESUMED", said: 0, offset: 0) == nil)
        #expect(TrackFlags.countdown(3_725_000) == "1:02:05")
    }

    @Test func flagsRedUntilGreen() {
        // Spa 2026 Q3: "TRACK CLEAR" 31 s after the red, but the session stayed stopped until 15:04.
        let spa = Self.utc("2026-07-18T14:00:00Z")
        let rc = lines(
            #"00:56:55.000{"Messages":[{"Utc":"2026-07-18T14:56:55","Category":"Flag","Flag":"RED","Scope":"Track","Message":"RED FLAG"}]}"#,
            #"00:57:26.000{"Messages":{"25":{"Utc":"2026-07-18T14:57:26","Category":"Flag","Flag":"CLEAR","Scope":"Track","Message":"TRACK CLEAR"}}}"#,
            #"01:04:00.000{"Messages":{"31":{"Utc":"2026-07-18T15:04:00","Category":"Flag","Flag":"GREEN","Scope":"Track","Message":"GREEN LIGHT - PIT EXIT OPEN"}}}"#
        )
        let flags = TrackFlags.build(trackStatus: [], raceControl: rc, streamStart: spa, gmtOffsetSeconds: 7200)
        #expect(flags.at(Self.utc("2026-07-18T15:00:00Z")).status == .red)
        #expect(flags.at(Self.utc("2026-07-18T15:04:01Z")).status == .clear)
        #expect(flags.spans == [FlagSpan(kind: .red, start: Self.utc("2026-07-18T14:56:55Z"), end: Self.utc("2026-07-18T15:04:00Z"))])
    }

    @Test func flagsSafetyCarInThisLap() {
        let t0 = Self.t0
        let flags = TrackFlags.build(
            trackStatus: lines(#"00:00:00.000{"Status":"4","Message":"SCDeployed"}"#, #"00:05:00.000{"Status":"1","Message":"AllClear"}"#),
            raceControl: lines(#"00:03:20.000{"Messages":[{"Utc":"\#(iso(t0 + 200_000))","Category":"SafetyCar","Message":"SAFETY CAR IN THIS LAP"}]}"#),
            streamStart: t0, gmtOffsetSeconds: 0)
        #expect(flags.at(t0 + 100_000).status == .safetyCar)
        #expect(flags.at(t0 + 100_000).caption == "Safety car")
        #expect(flags.at(t0 + 250_000).status == .safetyCarInThisLap)
        #expect(flags.at(t0 + 310_000).status == .clear)
        #expect(flags.spans == [FlagSpan(kind: .safetyCar, start: t0, end: t0 + 300_000)])
    }

    @Test func realQualifyingRedOutlastsTrackStatus() throws {
        let flags = TrackFlags.build(trackStatus: try Fixture.lines("sp26-quali/TrackStatus.jsonStream"),
                                     raceControl: try Fixture.lines("sp26-quali/RaceControlMessages.jsonStream"),
                                     streamStart: Fixture.qualiStart, gmtOffsetSeconds: -10800)
        // check:qualiRedFlagUtc = [1794074543000] (race control's Utc has no "Z");
        // check:qualiTrackStatus: 5 at 1794074545775, back to 1 at 1794074702779;
        // check:qualiGreensAfterRed = []: still stopped when the window ends.
        #expect(flags.at(1_794_074_542_999).status == .clear)
        #expect(flags.at(1_794_074_546_775).status == .red)
        #expect(flags.at(1_794_074_702_779 + 60_000).status == .red)
        #expect(flags.spans == [FlagSpan(kind: .red, start: 1_794_074_543_000, end: nil)])
        // The track's yellow at the window's start (status 2) has no caption.
        #expect(flags.at(Fixture.qualiStart + 1000).status == .yellow)
        #expect(flags.at(Fixture.qualiStart + 1000).caption == nil)
    }
}

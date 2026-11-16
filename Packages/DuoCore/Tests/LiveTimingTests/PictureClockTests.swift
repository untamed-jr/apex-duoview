import Foundation
import Testing
@testable import LiveTiming

@Suite struct PictureClockTests {
    static let start: UTCms = 1_794_154_179_389

    @Test func programDatePlusOffset() throws {
        let date = Date(timeIntervalSince1970: 1_794_157_403.965)
        let clock = PictureClock()
        #expect(PictureClock.defaultOffsetMs == -7000)
        #expect(clock.offsetMs == -7000)
        // The program date wins over the session start, and is not an estimate.
        let r = try #require(clock.time(programDate: date, sessionStart: Self.start, playerSeconds: 12))
        #expect(r.t == 1_794_157_403_965 - 7000)
        #expect(!r.estimated)
        let own = try #require(PictureClock(offsetMs: -2500).time(programDate: date, sessionStart: nil, playerSeconds: 0))
        #expect(own.t == 1_794_157_403_965 - 2500)
        #expect(!own.estimated)
    }

    @Test func estimatedWithoutProgramDate() throws {
        let r = try #require(PictureClock().time(programDate: nil, sessionStart: Self.start, playerSeconds: 3224.576))
        #expect(r.t == Self.start + 3_224_576 - 7000)
        #expect(r.estimated)
        // A program date that is no moment counts as none.
        let bad = Date(timeIntervalSince1970: .infinity)
        let fallback = try #require(PictureClock(offsetMs: 0).time(programDate: bad, sessionStart: Self.start, playerSeconds: 1.5))
        #expect(fallback.t == Self.start + 1500)
        #expect(fallback.estimated)
    }

    @Test func nilWithoutAnyClock() {
        let clock = PictureClock()
        #expect(clock.time(programDate: nil, sessionStart: nil, playerSeconds: 10) == nil)
        // A player position that is no number gives no estimate (and never traps).
        for seconds in [Double.nan, .infinity, -.infinity, 1e300] {
            #expect(clock.time(programDate: nil, sessionStart: Self.start, playerSeconds: seconds) == nil)
        }
        #expect(clock.time(programDate: Date(timeIntervalSince1970: .nan), sessionStart: nil, playerSeconds: 10) == nil)
    }

    @Test func extremeValuesSaturate() throws {
        let far = try #require(PictureClock(offsetMs: .max).time(programDate: nil, sessionStart: .max - 10, playerSeconds: 100))
        #expect(far.t == .max)
        let early = try #require(PictureClock(offsetMs: .min).time(programDate: nil, sessionStart: 0, playerSeconds: -5))
        #expect(early.t == .min)
    }
}

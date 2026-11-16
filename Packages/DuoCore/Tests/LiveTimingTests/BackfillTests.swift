import Testing
import F1TV
@testable import LiveTiming

struct BackfillTests {
    @Test func backfillCompleteWithin30s() {
        let joined: UTCms = 1_794_157_403_965
        #expect(Backfill.isComplete(archiveLast: joined - 29_999, joinedAt: joined))
        #expect(Backfill.isComplete(archiveLast: joined - 1, joinedAt: joined))
        // Android's check is strict: exactly 30 s short is not yet complete.
        #expect(!Backfill.isComplete(archiveLast: joined - 30_000, joinedAt: joined))
        #expect(!Backfill.isComplete(archiveLast: joined - 600_000, joinedAt: joined))
        // Reaching past the join.
        #expect(Backfill.isComplete(archiveLast: joined + 5_000, joinedAt: joined))
        // Far apart values don't overflow.
        #expect(!Backfill.isComplete(archiveLast: .min, joinedAt: .max))
        #expect(Backfill.isComplete(archiveLast: .max, joinedAt: .min))
    }

    @Test func backfillRetriesEveryTwoMinutesForSixHours() {
        #expect(Backfill.spacing == .seconds(120))
        #expect(Backfill.maxAttempts == 180)
        #expect(Backfill.spacing * Backfill.maxAttempts == .seconds(6 * 3600))
    }

    @Test func rebaseKeepsTheLinesBeforeTheJoin() {
        let archiveStart: UTCms = 1_000_000
        let source = lines(#"00:00:01.000{"a":1}"#, #"00:00:05.000{"a":2}"#, #"00:00:09.000{"a":3}"#, #"00:00:12.000{"a":4}"#)
        let rebased = Backfill.rebase(source, archiveStart: archiveStart, newStart: archiveStart + 2_000, until: archiveStart + 9_000)
        #expect(rebased == [StreamLine(offsetMs: 3_000, json: .object(["a": .number(2)]))])
        // A stream start long before the archive's, as the live feed's head start.
        let early = Backfill.rebase(source, archiveStart: archiveStart, newStart: 0, until: .max)
        #expect(early.map(\.offsetMs) == [1_001_000, 1_005_000, 1_009_000, 1_012_000])
    }

    @Test func archiveLastIsTheLatestCarSample() throws {
        let positions = PositionSeries.parse(lines: try Fixture.lines("sp26-race/Position.z.jsonStream"))
        let last = try #require(Backfill.archiveLast(positions))
        #expect(positions.cars.values.allSatisfy { ($0.last ?? .min) <= last })
        #expect(Backfill.archiveLast(PositionSeries(cars: [:])) == nil)
    }
}

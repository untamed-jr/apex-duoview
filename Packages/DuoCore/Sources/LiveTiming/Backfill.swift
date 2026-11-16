import Foundation
import F1TV

/// Topping a live session up from F1's archive (Android's `LiveTimingFeed.backfill`). Live
/// timing only sends what happens from the moment it is joined; F1 writes the archive as the
/// session goes but publishes it only once it is over, so the app asks every `spacing`, up to
/// `maxAttempts` times (6 h), until the archive reaches within 30 s of the moment it joined.
public enum Backfill {
    public static let spacing: Duration = .seconds(120)
    public static let maxAttempts = 180
    /// The archive is close enough to the live timing once it reaches this near the join.
    public static let completeGapMs: Int64 = 30_000

    /// The archive's files a top-up reads, besides Heartbeat (for the archive's own start,
    /// `ArchiveClock.streamStart`). Each is optional: a missing one keeps the live opening state.
    public static let topics: [String] = [
        "Position.z", "TimingData", "TimingAppData", "SessionStatus", "RaceControlMessages", "TrackStatus",
        "LapCount", "ExtrapolatedClock", "WeatherData", "TeamRadio",
    ]

    /// Whether the archive, whose last car position is at `archiveLast`, reaches within 30 s of
    /// `joinedAt` (the live feed's first message): strictly less than 30 000 ms short, as
    /// Android's check. An archive reaching past the join is complete.
    public static func isComplete(archiveLast: UTCms, joinedAt: UTCms) -> Bool {
        F1Values.sub(joinedAt, archiveLast) < completeGapMs
    }

    /// The last car position in the archive's positions; nil when it has none.
    public static func archiveLast(_ positions: PositionSeries) -> UTCms? {
        positions.cars.values.compactMap(\.last).max()
    }

    /// An archive stream's lines (offsets from `archiveStart`) from `newStart` up to, not
    /// including, `until`, with offsets from `newStart` (Android's `rebaseStream`). Lines are in
    /// the archive's order; the first at or past `until` ends it.
    public static func rebase(_ lines: [StreamLine], archiveStart: UTCms, newStart: UTCms, until: UTCms) -> [StreamLine] {
        var out: [StreamLine] = []
        for line in lines {
            let utc = F1Values.add(archiveStart, line.offsetMs)
            if utc >= until { break }
            if utc < newStart { continue }
            out.append(StreamLine(offsetMs: F1Values.sub(utc, newStart), json: line.json))
        }
        return out
    }
}

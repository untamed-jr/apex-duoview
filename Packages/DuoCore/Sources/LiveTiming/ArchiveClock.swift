import Foundation
import F1TV

/// Ties an archive's stream offsets to UTC.
public enum ArchiveClock {
    static let samples = 50
    /// The heartbeat and the cars' own clocks may disagree by this much before the cars win.
    static let slackMs: Int64 = 60_000

    /// The median of `Utc − offset` over the first 50 heartbeat beats, so one odd beat can't
    /// move every time in the session. Where Position's own timestamps imply a start more than
    /// 60 s away (the 2026 Mexico race's heartbeat put everything 33 h late), Position wins.
    /// Nil when neither stream gives a clock.
    public static func streamStart(heartbeat: [StreamLine], positions: [StreamLine]) -> UTCms? {
        var beats: [UTCms] = []
        for line in heartbeat where beats.count < samples {
            if let utc = F1Values.utc(line.json["Utc"].string) { beats.append(utc - line.offsetMs) }
        }
        let fromPositions = median(PositionSeries.impliedStreamStarts(positions, limit: samples))
        guard let fromHeartbeat = median(beats) else { return fromPositions }
        if let p = fromPositions, abs(p - fromHeartbeat) > slackMs { return p }
        return fromHeartbeat
    }

    /// The upper middle value, as Android takes it.
    static func median(_ values: [UTCms]) -> UTCms? {
        guard !values.isEmpty else { return nil }
        return values.sorted()[values.count / 2]
    }
}

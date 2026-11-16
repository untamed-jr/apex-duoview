import Foundation

/// What CarData's channel 45 carries, which decides Race Engineer's light.
///
/// Before 2026 it is DRS (10, 12 and 14 mean the flap is open). The 2026 rules replace DRS with
/// active aero and an overtake mode, and the São Paulo 2026 CarData has no channel 45 at all
/// (`ReadoutsTests.channel45MeaningFromFixture`), so for 2026 the light is shown only when the
/// data shows the channel moving. It is never shown with a meaning the data doesn't carry.
public enum Channel45Meaning: Sendable, Equatable {
    case drs
    case activeAero
    /// Nothing useful: no light.
    case absent

    /// The light's label: "DRS", "Aero", or none.
    public var label: String? {
        switch self {
        case .drs: return "DRS"
        case .activeAero: return "Aero"
        case .absent: return nil
        }
    }

    /// The meaning for a season's car data. Before 2026, DRS. From 2026 (or with no year), only
    /// what the samples show: a channel that changes is active aero; one that never changes (left
    /// out reads 0, as `CarDataWindow` parses it) is absent.
    public static func of(year: Int?, samples: [String: [CarSample]]) -> Channel45Meaning {
        if let year, year < 2026 { return .drs }
        var first: Int?
        for sample in samples.values.joined() {
            guard let seen = first else { first = sample.ch45; continue }
            if sample.ch45 != seen { return .activeAero }
        }
        return .absent
    }

    /// Whether the light is lit for a channel 45 value; nil when there is no light.
    func lit(_ value: Int) -> Bool? {
        switch self {
        case .drs: return [10, 12, 14].contains(value)
        // No 2026 data carries the channel yet: any non-zero value counts as engaged.
        case .activeAero: return value != 0
        case .absent: return nil
        }
    }
}

/// Race Engineer's live readouts at one moment.
public struct Readout: Sendable, Equatable {
    public var speedKmh: Int
    public var gear: Int
    public var rpm: Int
    /// 0–100 (F1 sends up to 104 at times; the bars stop at 100).
    public var throttle: Int
    /// 0–100.
    public var brake: Int
    /// The DRS or active-aero light; nil when channel 45 carries nothing (`Channel45Meaning.absent`).
    public var aero: Bool?
    /// The sample is more than 5 s older than picture time: the values hold and grey.
    public var stale: Bool

    public init(speedKmh: Int, gear: Int, rpm: Int, throttle: Int, brake: Int, aero: Bool?, stale: Bool) {
        self.speedKmh = speedKmh
        self.gear = gear
        self.rpm = rpm
        self.throttle = throttle
        self.brake = brake
        self.aero = aero
        self.stale = stale
    }
}

public enum Readouts {
    /// One car's readouts at `t` (picture time): its latest sample at or before `t`, held while
    /// the data pauses and stale once more than 5 s old (`CarDataWindow.staleMs`). Nil before the
    /// first sample. `samples` are oldest first, as `CarDataWindow.parse` gives them.
    public static func at(_ t: UTCms, samples: [CarSample], channel45: Channel45Meaning) -> Readout? {
        guard let (sample, stale) = CarDataWindow.readout(samples, at: t) else { return nil }
        return Readout(
            speedKmh: sample.speedKmh,
            gear: sample.gear,
            rpm: sample.rpm,
            throttle: min(max(sample.throttle, 0), 100),
            brake: min(max(sample.brake, 0), 100),
            aero: channel45.lit(sample.ch45),
            stale: stale
        )
    }
}

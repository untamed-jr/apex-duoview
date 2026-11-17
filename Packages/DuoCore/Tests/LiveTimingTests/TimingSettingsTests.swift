import Foundation
import Testing
import Library
@testable import LiveTiming

@Suite struct TimingSettingsTests {
    @Test func startingValues() {
        let s = TimingSettings(store: MemoryStore())
        #expect(s.offsetMs == -7000)
        #expect(s.mapTurn(circuitKey: 14) == 0)
        #expect(s.pitLossMs(circuitKey: 14) == nil)
        #expect(s.panelFrame("map", posture: "landscape") == nil)
        #expect(s.showWholeRace == false)
        #expect(s.trackerDelayHalfSeconds == 0)
        #expect(s.hiddenCards == [])
        #expect(s.speedOnMobileData == true)
    }

    @Test func nudgeAndReset() {
        let mem = MemoryStore()
        let s = TimingSettings(store: mem)
        #expect(s.offsetMs == -7000)
        s.nudge(by: 1)
        #expect(s.offsetMs == -6000)
        #expect(TimingSettings(store: mem).offsetMs == -6000)  // kept
        s.nudge(by: -3)
        #expect(s.offsetMs == -9000)
        s.resetOffset()
        #expect(s.offsetMs == -7000)
        #expect(TimingSettings(store: mem).offsetMs == -7000)
        // Set directly; huge nudges stop at the limit instead of trapping.
        s.offsetMs = 1500
        #expect(TimingSettings(store: mem).offsetMs == 1500)
        s.nudge(by: .max)
        #expect(s.offsetMs == 60_000)
        s.nudge(by: .min)
        s.nudge(by: .min)
        #expect(s.offsetMs == -60_000)
        s.nudge(by: 1)
        #expect(s.offsetMs == -59_000)
    }

    /// ±60 s either way, when set, nudged and read back (a stored value from elsewhere).
    @Test func offsetStaysWithinAMinute() throws {
        let mem = MemoryStore()
        let s = TimingSettings(store: mem)
        s.offsetMs = 61_000
        #expect(s.offsetMs == 60_000)
        s.offsetMs = -3_600_000
        #expect(s.offsetMs == -60_000)
        s.offsetMs = 60_000
        s.nudge(by: 1)
        #expect(s.offsetMs == 60_000)
        mem.set(try JSONEncoder().encode(Int64.max), forKey: TimingSettings.offsetKey)
        #expect(s.offsetMs == 60_000)
        mem.set(try JSONEncoder().encode(Int64(-90_000)), forKey: TimingSettings.offsetKey)
        #expect(s.offsetMs == -60_000)
        s.nudge(by: 2)
        #expect(s.offsetMs == -58_000)
    }

    @Test func trackerDelayNudgesWithinItsRange() {
        let mem = MemoryStore()
        let s = TimingSettings(store: mem)
        #expect(s.nudgeTrackerDelay(by: 3) == 3)
        #expect(s.nudgeTrackerDelay(by: -1) == 2)
        #expect(TimingSettings(store: mem).trackerDelayHalfSeconds == 2)
        #expect(s.nudgeTrackerDelay(by: -5) == 0)
        #expect(s.nudgeTrackerDelay(by: .max) == 40)
        #expect(s.nudgeTrackerDelay(by: 1) == 40)
        #expect(s.nudgeTrackerDelay(by: .min) == 0)
        #expect(s.trackerDelayHalfSeconds == 0)
    }

    @Test func hiddenCardToggles() {
        let mem = MemoryStore()
        let s = TimingSettings(store: mem)
        #expect(s.toggleHiddenCard(1033))
        #expect(s.toggleHiddenCard(1016))
        #expect(TimingSettings(store: mem).hiddenCards == [1016, 1033])
        #expect(!s.toggleHiddenCard(1033))
        #expect(s.hiddenCards == [1016])
        #expect(!s.toggleHiddenCard(1016))
        #expect(s.hiddenCards.isEmpty)
    }

    /// Many threads at once: each atomic change lands once (a get then a set would lose some).
    @Test func atomicChangesDontLoseUpdates() async {
        let s = TimingSettings(store: MemoryStore())
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask { s.toggleHiddenCard(i) }
                group.addTask { s.nudgeTrackerDelay(by: 1) }
            }
        }
        #expect(s.hiddenCards == Set(0..<20))
        #expect(s.trackerDelayHalfSeconds == 20)
    }

    @Test func perCircuitTurnAndPitLossPersist() {
        let mem = MemoryStore()
        let s = TimingSettings(store: mem)
        s.setMapTurn(90, circuitKey: 14)
        s.setMapTurn(-45.5, circuitKey: 152)
        s.setPitLossMs(21_500, circuitKey: 14)
        let again = TimingSettings(store: mem)
        #expect(again.mapTurn(circuitKey: 14) == 90)
        #expect(again.mapTurn(circuitKey: 152) == -45.5)
        #expect(again.mapTurn(circuitKey: 7) == 0)
        #expect(again.pitLossMs(circuitKey: 14) == 21_500)
        #expect(again.pitLossMs(circuitKey: 152) == nil)
        // nil forgets a circuit's pit loss.
        again.setPitLossMs(nil, circuitKey: 14)
        #expect(s.pitLossMs(circuitKey: 14) == nil)
        #expect(mem.data(forKey: TimingSettings.pitLossKey(14)) == nil)
    }

    private func circle(lossMs: Int, stops: Int) -> PitCircleState {
        PitCircleState(referenceLapMs: 72_000, greenLaps: 5, pitLossMs: lossMs, measuredStops: stops, leader: "1",
                       lap: 30, cars: [])
    }

    @Test func measuredPitLossIsKeptPerCircuit() {
        let mem = MemoryStore()
        let s = TimingSettings(store: mem)
        // Too few stops: nothing kept.
        #expect(s.rememberPitLoss(circle(lossMs: 21_000, stops: 0), circuitKey: 14, sessionKey: "11412") == false)
        #expect(s.rememberPitLoss(circle(lossMs: 21_000, stops: 2), circuitKey: 14, sessionKey: "11412") == false)
        #expect(s.pitLossMs(circuitKey: 14) == nil)
        // Three clean stops: kept for that circuit only, and read back by a new instance.
        #expect(s.rememberPitLoss(circle(lossMs: 21_400, stops: 3), circuitKey: 14, sessionKey: "11412"))
        #expect(TimingSettings(store: mem).pitLossMs(circuitKey: 14) == 21_400)
        #expect(s.pitLossMs(circuitKey: 152) == nil)
        // The same value again doesn't write; a new measurement replaces it.
        #expect(s.rememberPitLoss(circle(lossMs: 21_400, stops: 4), circuitKey: 14, sessionKey: "11412") == false)
        #expect(s.rememberPitLoss(circle(lossMs: 20_900, stops: 7), circuitKey: 14, sessionKey: "11412"))
        #expect(s.pitLossMs(circuitKey: 14) == 20_900)
        // Outside one ordinary stop's range (10–45 s): left as it was.
        #expect(s.rememberPitLoss(circle(lossMs: 9_999, stops: 9), circuitKey: 14, sessionKey: "11412") == false)
        #expect(s.rememberPitLoss(circle(lossMs: 45_001, stops: 9), circuitKey: 14, sessionKey: "11412") == false)
        #expect(s.pitLossMs(circuitKey: 14) == 20_900)
        #expect(s.rememberPitLoss(circle(lossMs: 10_000, stops: 3), circuitKey: 7, sessionKey: "11412"))
        #expect(s.rememberPitLoss(circle(lossMs: 45_000, stops: 3), circuitKey: 8, sessionKey: "11412"))
        #expect(s.pitLossMs(circuitKey: 7) == 10_000 && s.pitLossMs(circuitKey: 8) == 45_000)
    }

    @Test func rememberedPitLossFeedsTheNextSession() throws {
        // What São Paulo's race measured, kept, is the fallback a session without stops uses.
        let s = TimingSettings(store: MemoryStore())
        #expect(s.rememberPitLoss(circle(lossMs: 23_100, stops: 5), circuitKey: 14, sessionKey: "11412"))
        let stored = try #require(s.pitLossMs(circuitKey: 14))
        #expect(PitCircle.pitLossMs(sessionStops: [], storedMs: Int(stored)) == 23_100)
        // The session's own stops still win.
        #expect(PitCircle.pitLossMs(sessionStops: [20_000], storedMs: Int(stored)) == 20_000)
    }

    @Test func aSessionNeverReadsBackItsOwnPitLoss() {
        let mem = MemoryStore()
        let s = TimingSettings(store: mem)
        s.setPitLossMs(22_800, circuitKey: 14)
        // The viewer's value holds for every session.
        #expect(s.pitLossMs(circuitKey: 14, notFrom: "11412") == 22_800)
        // The race measures 21 400 ms: kept for the circuit, but the race itself (a rewind to
        // before its stops) still reads what was there before it.
        #expect(s.rememberPitLoss(circle(lossMs: 21_400, stops: 3), circuitKey: 14, sessionKey: "11412"))
        #expect(s.pitLossMs(circuitKey: 14) == 21_400)
        #expect(s.pitLossMs(circuitKey: 14, notFrom: "11412") == 22_800)
        #expect(s.pitLossMs(circuitKey: 14, notFrom: "11413") == 21_400)
        // Its later measurements keep what was there before it, across a new instance.
        #expect(s.rememberPitLoss(circle(lossMs: 20_900, stops: 6), circuitKey: 14, sessionKey: "11412"))
        let again = TimingSettings(store: mem)
        #expect(again.pitLossMs(circuitKey: 14, notFrom: "11412") == 22_800)
        #expect(again.pitLossMs(circuitKey: 14, notFrom: "11413") == 20_900)
        // Another session measuring the same value takes it over: the first race reads it now.
        #expect(again.rememberPitLoss(circle(lossMs: 20_900, stops: 3), circuitKey: 14, sessionKey: "11413"))
        #expect(again.pitLossMs(circuitKey: 14, notFrom: "11412") == 20_900)
        #expect(again.pitLossMs(circuitKey: 14, notFrom: "11413") == 20_900)
        #expect(again.rememberPitLoss(circle(lossMs: 20_900, stops: 4), circuitKey: 14, sessionKey: "11413") == false)
        // A session with nothing before it reads nothing (the typical 22 s), never its own.
        #expect(again.rememberPitLoss(circle(lossMs: 24_000, stops: 3), circuitKey: 8, sessionKey: "9000"))
        #expect(again.pitLossMs(circuitKey: 8, notFrom: "9000") == nil)
        #expect(again.pitLossMs(circuitKey: 8, notFrom: "9001") == 24_000)
        // The viewer setting it again: no session's, for everyone.
        again.setPitLossMs(23_000, circuitKey: 8)
        #expect(again.pitLossMs(circuitKey: 8, notFrom: "9000") == 23_000)
        #expect(mem.data(forKey: TimingSettings.pitLossFromKey(8)) == nil)
        // A value kept before sessions were recorded holds for every session.
        let legacy = MemoryStore()
        legacy.set(Data("21000".utf8), forKey: TimingSettings.pitLossKey(14))
        #expect(TimingSettings(store: legacy).pitLossMs(circuitKey: 14, notFrom: "11412") == 21_000)
    }

    @Test func otherSettingsPersist() {
        let mem = MemoryStore()
        let s = TimingSettings(store: mem)
        let frame = CGRect(x: 12, y: 40.5, width: 320, height: 180)
        s.setPanelFrame(frame, panel: "map", posture: "landscape")
        s.showWholeRace = true
        s.trackerDelayHalfSeconds = 7
        s.hiddenCards = [1033, 1016]
        s.speedOnMobileData = false
        let again = TimingSettings(store: mem)
        #expect(again.panelFrame("map", posture: "landscape") == frame)
        #expect(again.panelFrame("map", posture: "portrait") == nil)
        #expect(again.panelFrame("leaderboard", posture: "landscape") == nil)
        #expect(again.showWholeRace)
        #expect(again.trackerDelayHalfSeconds == 7)
        #expect(again.hiddenCards == [1016, 1033])
        #expect(!again.speedOnMobileData)
        again.setPanelFrame(nil, panel: "map", posture: "landscape")
        #expect(s.panelFrame("map", posture: "landscape") == nil)
        // Every key is under "timing.".
        #expect(TimingSettings.keys.allSatisfy { $0.hasPrefix("timing.") })
        #expect(TimingSettings.mapTurnKey(14).hasPrefix("timing."))
        #expect(TimingSettings.pitLossKey(14).hasPrefix("timing."))
        #expect(TimingSettings.pitLossFromKey(14).hasPrefix("timing."))
        #expect(TimingSettings.panelFrameKey("map", posture: "landscape").hasPrefix("timing."))
    }

    @Test func corruptValuesFallBack() throws {
        let mem = MemoryStore()
        let garbage = Data("garbage".utf8)
        for key in TimingSettings.keys + [TimingSettings.mapTurnKey(14), TimingSettings.pitLossKey(14),
                                          TimingSettings.pitLossFromKey(14),
                                          TimingSettings.panelFrameKey("map", posture: "landscape")] {
            mem.set(garbage, forKey: key)
        }
        let s = TimingSettings(store: mem)
        #expect(s.offsetMs == -7000)
        #expect(s.mapTurn(circuitKey: 14) == 0)
        #expect(s.pitLossMs(circuitKey: 14) == nil)
        #expect(s.pitLossMs(circuitKey: 14, notFrom: "11412") == nil)
        #expect(s.panelFrame("map", posture: "landscape") == nil)
        #expect(s.showWholeRace == false)
        #expect(s.trackerDelayHalfSeconds == 0)
        #expect(s.hiddenCards == [])
        #expect(s.speedOnMobileData == true)
        // An unreadable session record: the value is nobody's, so it holds.
        mem.set(Data("21000".utf8), forKey: TimingSettings.pitLossKey(14))
        #expect(s.pitLossMs(circuitKey: 14, notFrom: "11412") == 21_000)
        mem.set(nil, forKey: TimingSettings.pitLossKey(14))

        // Readable JSON of the wrong type or shape is as bad.
        mem.set(Data(#""soon""#.utf8), forKey: TimingSettings.offsetKey)
        mem.set(Data("[1,2,3]".utf8), forKey: TimingSettings.panelFrameKey("map", posture: "landscape"))
        mem.set(Data("-5".utf8), forKey: TimingSettings.pitLossKey(14))
        mem.set(Data("1".utf8), forKey: TimingSettings.showWholeRaceKey)
        #expect(s.offsetMs == -7000)
        #expect(s.panelFrame("map", posture: "landscape") == nil)
        #expect(s.pitLossMs(circuitKey: 14) == nil)
        #expect(s.showWholeRace == false)  // a number is not a Bool

        // A value that can't be encoded (not a number) keeps the stored one.
        s.setMapTurn(30, circuitKey: 14)
        s.setMapTurn(.nan, circuitKey: 14)
        s.setMapTurn(.infinity, circuitKey: 14)
        #expect(s.mapTurn(circuitKey: 14) == 30)
        let frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        s.setPanelFrame(frame, panel: "map", posture: "landscape")
        s.setPanelFrame(CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1), panel: "map", posture: "landscape")
        #expect(s.panelFrame("map", posture: "landscape") == frame)
    }

    @Test func trackerDelayClamped() {
        let mem = MemoryStore()
        let s = TimingSettings(store: mem)
        s.trackerDelayHalfSeconds = 50
        #expect(s.trackerDelayHalfSeconds == 40)
        s.trackerDelayHalfSeconds = -3
        #expect(s.trackerDelayHalfSeconds == 0)
        s.trackerDelayHalfSeconds = 40
        #expect(s.trackerDelayHalfSeconds == 40)
        s.trackerDelayHalfSeconds = .min
        #expect(s.trackerDelayHalfSeconds == 0)
        // A stored value out of range is clamped when read, too.
        mem.set(Data("99".utf8), forKey: TimingSettings.trackerDelayKey)
        #expect(s.trackerDelayHalfSeconds == 40)
        mem.set(Data("-1".utf8), forKey: TimingSettings.trackerDelayKey)
        #expect(s.trackerDelayHalfSeconds == 0)
    }

    @Test func concurrentNudgesAllCount() async {
        let s = TimingSettings(store: MemoryStore())
        s.offsetMs = -60_000
        // 120 one-second nudges take it exactly from one limit to the other.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<120 { group.addTask { s.nudge(by: 1) } }
        }
        #expect(s.offsetMs == 60_000)
    }
}

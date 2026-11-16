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
        // Set directly; huge nudges saturate instead of trapping.
        s.offsetMs = 1500
        #expect(TimingSettings(store: mem).offsetMs == 1500)
        s.nudge(by: .max)
        #expect(s.offsetMs == .max)
        s.nudge(by: .min)
        s.nudge(by: .min)
        #expect(s.offsetMs == .min)
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
        #expect(TimingSettings.panelFrameKey("map", posture: "landscape").hasPrefix("timing."))
    }

    @Test func corruptValuesFallBack() throws {
        let mem = MemoryStore()
        let garbage = Data("garbage".utf8)
        for key in TimingSettings.keys + [TimingSettings.mapTurnKey(14), TimingSettings.pitLossKey(14),
                                          TimingSettings.panelFrameKey("map", posture: "landscape")] {
            mem.set(garbage, forKey: key)
        }
        let s = TimingSettings(store: mem)
        #expect(s.offsetMs == -7000)
        #expect(s.mapTurn(circuitKey: 14) == 0)
        #expect(s.pitLossMs(circuitKey: 14) == nil)
        #expect(s.panelFrame("map", posture: "landscape") == nil)
        #expect(s.showWholeRace == false)
        #expect(s.trackerDelayHalfSeconds == 0)
        #expect(s.hiddenCards == [])
        #expect(s.speedOnMobileData == true)

        // Readable JSON of the wrong type or shape is as bad.
        mem.set(Data(#""soon""#.utf8), forKey: TimingSettings.offsetKey)
        mem.set(Data("[1,2,3]".utf8), forKey: TimingSettings.panelFrameKey("map", posture: "landscape"))
        mem.set(Data("-5".utf8), forKey: TimingSettings.pitLossKey(14))
        mem.set(Data("1".utf8), forKey: TimingSettings.speedOnMobileDataKey)
        #expect(s.offsetMs == -7000)
        #expect(s.panelFrame("map", posture: "landscape") == nil)
        #expect(s.pitLossMs(circuitKey: 14) == nil)
        #expect(s.speedOnMobileData == true)

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
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<200 { group.addTask { s.nudge(by: 1) } }
        }
        #expect(s.offsetMs == -7000 + 200_000)
    }
}

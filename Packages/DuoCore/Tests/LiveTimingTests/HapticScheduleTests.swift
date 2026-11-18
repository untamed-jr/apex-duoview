import Testing
import Foundation
@testable import LiveTiming

@Suite struct HapticScheduleTests {
    @Test func spacingTwoSeconds() {
        var s = HapticSchedule()
        s.offer(.yellow, now: 10)
        #expect(s.due(now: 10) == .yellow)
        s.offer(.pits, now: 10.5)
        #expect(s.due(now: 10.5) == nil)
        #expect(s.due(now: 11.99) == nil)
        #expect(s.due(now: 12) == .pits)
        #expect(s.due(now: 20) == nil)
    }

    @Test func strongerReplacesWaiting() {
        var s = HapticSchedule()
        s.offer(.yellow, now: 0)
        #expect(s.due(now: 0) == .yellow)
        s.offer(.purpleSector, now: 1)
        s.offer(.safetyCar, now: 1.5)
        #expect(s.due(now: 2) == .safetyCar)
    }

    @Test func weakerDroppedWhileStrongerWaits() {
        var s = HapticSchedule()
        s.offer(.yellow, now: 0)
        _ = s.due(now: 0)
        s.offer(.red, now: 1)
        s.offer(.purpleSector, now: 1.2)
        s.offer(.red, now: 1.3)
        #expect(s.due(now: 2) == .red)
        #expect(s.due(now: 10) == nil)
    }

    @Test func priorityOrder() {
        #expect(HapticKind.allCases == [.red, .safetyCar, .vsc, .chequered, .yellow, .pits, .purpleSector])
        #expect(HapticKind.allCases.map(\.priority) == Array(0..<7))
        #expect(HapticKind.from(.yellow) == .yellow)
        #expect(HapticKind.from(.pit(car: "1")) == .pits)
        #expect(HapticKind.from(.purpleSector(car: "1")) == .purpleSector)
        #expect(HapticKind.from(.radio(car: "1")) == nil)
        #expect(HapticKind.from(.out(car: "1")) == nil)
        #expect(HapticKind.from(.passed(car: "1", other: "2", position: 3)) == nil)
    }

    @Test func oddClocksNeverTrap() {
        var s = HapticSchedule()
        s.offer(.red, now: .nan)
        #expect(s.due(now: .infinity) == nil)
        s.offer(.red, now: 5)
        #expect(s.due(now: .nan) == nil)
        #expect(s.due(now: 5) == .red)
        // The clock went backwards: not held for ever.
        s.offer(.vsc, now: 1)
        #expect(s.due(now: 1) == .vsc)
        s.reset()
        #expect(s.pending == nil)
    }
}

import Testing
@testable import Multiview

@Suite struct HingeMixerTests {
    @Test func levelsAtEnds() {
        #expect(HingeMixer.levels(angle: 70) == MixLevels(commentary: 0, radio: 1))
        #expect(HingeMixer.levels(angle: 160) == MixLevels(commentary: 1, radio: 0))
        #expect(HingeMixer.levels(angle: 30) == MixLevels(commentary: 0, radio: 1))
        #expect(HingeMixer.levels(angle: 180) == MixLevels(commentary: 1, radio: 0))
        #expect(HingeMixer.levels(angle: 115) == MixLevels(commentary: 0.5, radio: 0.5))
        let q = HingeMixer.levels(angle: 100)
        #expect(q.commentary + q.radio == 1)
    }

    @Test func deadZoneIgnoresJitter() {
        var mixer = HingeMixer()
        #expect(mixer.update(angle: 100) != nil)
        #expect(mixer.update(angle: 102) == nil)
        #expect(mixer.update(angle: 98) == nil)
        #expect(mixer.update(angle: 103) == nil)
    }

    @Test func smoothingFollowsAMove() {
        var mixer = HingeMixer()
        _ = mixer.update(angle: 100)
        // A step to 140: the smoothed angle gets 0.3 of the way each reading: 112, 120.4, 126.28.
        // 112 is 12 off the applied 100, past the dead zone, so it applies (not 140 at once).
        let first = mixer.update(angle: 140)
        #expect(first == HingeMixer.levels(angle: 112))
        // 120.4 is 8.4 on from 112: applies.
        #expect(mixer.update(angle: 140) == HingeMixer.levels(angle: 120.4))
        // 126.28 is 5.88 on: applies; then it settles towards 140.
        #expect(mixer.update(angle: 140) == HingeMixer.levels(angle: 126.28))
        var last = HingeMixer.levels(angle: 126.28)
        for _ in 0..<60 { if let l = mixer.update(angle: 140) { last = l } }
        // Within the dead zone of 140 and never past it.
        let gap = HingeMixer.levels(angle: 140).commentary - last.commentary
        #expect(gap >= 0 && gap <= Float(5.0 / 90.0) + 1e-6)
    }

    @Test func endsAlwaysReached() {
        // Closing towards the radio end: the last step inside the dead zone still applies.
        var mixer = HingeMixer()
        _ = mixer.update(angle: 80)
        var latest: MixLevels?
        for _ in 0..<80 { if let l = mixer.update(angle: 60) { latest = l } }
        #expect(latest == MixLevels(commentary: 0, radio: 1))
        // And the same at the commentary end.
        var other = HingeMixer()
        _ = other.update(angle: 150)
        latest = nil
        for _ in 0..<80 { if let l = other.update(angle: 175) { latest = l } }
        #expect(latest == MixLevels(commentary: 1, radio: 0))
        // Once there, more readings at the end do not re-apply.
        #expect(other.update(angle: 175) == nil)
    }
}

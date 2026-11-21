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

    @Test func nonFiniteReadingsAreIgnored() {
        for bad in [Double.nan, .infinity, -.infinity] {
            var mixer = HingeMixer()
            #expect(mixer.update(angle: bad) == nil)
            #expect(mixer.update(angle: 100) == HingeMixer.levels(angle: 100))
            #expect(mixer.update(angle: bad) == nil)
            // State was untouched: the next reading smooths from 100, not from the bad value.
            #expect(mixer.update(angle: 140) == HingeMixer.levels(angle: 112))
        }
        let nan = HingeMixer.levels(angle: .nan)
        #expect(!nan.commentary.isNaN && nan.commentary + nan.radio == 1)
        #expect(HingeMixer.levels(angle: .infinity) == MixLevels(commentary: 1, radio: 0))
        #expect(HingeMixer.levels(angle: -.infinity) == MixLevels(commentary: 0, radio: 1))
    }

    @Test func heldAtCommentaryEndReachesItExactly() {
        var mixer = HingeMixer()
        _ = mixer.update(angle: 150)
        var latest: MixLevels?
        for _ in 0..<6 { if let l = mixer.update(angle: 160) { latest = l } }
        #expect(latest == MixLevels(commentary: 1, radio: 0))
    }

    // MARK: Settling: the app's real input, each angle once

    /// Settles as the app does (a step on a short timer until settled; capped), keeping the last
    /// levels applied. Returns them and the number of steps taken.
    private func settled(_ mixer: inout HingeMixer, from start: MixLevels?) -> (levels: MixLevels?, steps: Int) {
        var latest = start
        var steps = 0
        while !mixer.isSettled, steps < 200 {
            if let l = mixer.settle() { latest = l }
            steps += 1
        }
        return (latest, steps)
    }

    @Test func oneReadingThenRestReachesTheReading() {
        // The hinge goes from flat-ish to 90° in one reading and stops: only that one reading comes.
        var mixer = HingeMixer()
        let first = mixer.update(angle: 160)
        #expect(first == MixLevels(commentary: 1, radio: 0))
        let moved = mixer.update(angle: 90)
        // The reading alone stops short, at 139° (0.3 of the way), and no more readings come.
        #expect(moved == HingeMixer.levels(angle: 139))
        #expect(!mixer.isSettled)
        let (levels, steps) = settled(&mixer, from: moved)
        #expect(mixer.isSettled)
        #expect(levels == HingeMixer.levels(angle: 90))
        // About 1.5 s at the app's 100 ms step.
        #expect(steps <= 20)
        // Settled: nothing more to do, and no further levels.
        #expect(mixer.settle() == nil)
    }

    @Test func oneReadingPastEachEndReachesTheEnd() {
        var closing = HingeMixer()
        _ = closing.update(angle: 150)
        let a = closing.update(angle: 40)
        let (radioEnd, _) = settled(&closing, from: a)
        #expect(radioEnd == MixLevels(commentary: 0, radio: 1))
        #expect(closing.isSettled)

        var opening = HingeMixer()
        _ = opening.update(angle: 80)
        let b = opening.update(angle: 180)
        let (commentaryEnd, _) = settled(&opening, from: b)
        #expect(commentaryEnd == MixLevels(commentary: 1, radio: 0))
        #expect(opening.isSettled)
    }

    @Test func aRampThenStopEndsWhereTheHingeStopped() {
        // 6° a reading from 160° down to 88°, each once, then nothing: without settling it lags
        // about 14° behind.
        var mixer = HingeMixer()
        var latest = mixer.update(angle: 160)
        for angle in stride(from: 154.0, through: 88.0, by: -6.0) {
            if let l = mixer.update(angle: angle) { latest = l }
        }
        #expect(latest != HingeMixer.levels(angle: 88))
        let (levels, _) = settled(&mixer, from: latest)
        #expect(levels == HingeMixer.levels(angle: 88))
    }

    @Test func aJitterReadingNeverAppliesWhenSettling() {
        var mixer = HingeMixer()
        #expect(mixer.update(angle: 100) != nil)
        for jitter in [102.0, 98.0, 103.0, 97.5] {
            #expect(mixer.update(angle: jitter) == nil)
            // Within the dead zone: nothing to settle, and settling applies nothing.
            #expect(mixer.isSettled)
            #expect(mixer.settle() == nil)
        }
    }

    @Test func aNewReadingWhileSettlingIsFollowed() {
        var mixer = HingeMixer()
        _ = mixer.update(angle: 160)
        var latest = mixer.update(angle: 90)
        // Two steps in, the hinge moves again (to 120°) and stops there.
        for _ in 0..<2 { if let l = mixer.settle() { latest = l } }
        if let l = mixer.update(angle: 120) { latest = l }
        let (levels, _) = settled(&mixer, from: latest)
        #expect(levels == HingeMixer.levels(angle: 120))
    }

    @Test func heldAtRadioEndReachesItExactly() {
        var mixer = HingeMixer()
        _ = mixer.update(angle: 80)
        var latest: MixLevels?
        for _ in 0..<6 { if let l = mixer.update(angle: 70) { latest = l } }
        #expect(latest == MixLevels(commentary: 0, radio: 1))
    }
}

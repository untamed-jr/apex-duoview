import Testing
@testable import Multiview

@Suite struct UnfoldWatchTests {
    @Test func closedToOpenIsAnUnfold() {
        for open in [Posture.flat, .book, .laptop] {
            var watch = UnfoldWatch()
            #expect(watch.change(from: .closed, to: open) == true)
        }
    }

    @Test func throughUnknownIsStillAnUnfold() {
        var watch = UnfoldWatch()
        #expect(watch.change(from: .closed, to: .unknown) == false)
        #expect(watch.mayBeOpening)
        #expect(watch.change(from: .unknown, to: .book) == true)
        #expect(!watch.mayBeOpening)
        // Several unknown readings in a row too.
        var slow = UnfoldWatch()
        #expect(slow.change(from: .closed, to: .unknown) == false)
        #expect(slow.see(.unknown) == false)
        #expect(slow.change(from: .unknown, to: .flat) == true)
    }

    @Test func unknownAloneNeverUnfolds() {
        // Nothing known before.
        var fresh = UnfoldWatch()
        #expect(fresh.change(from: .unknown, to: .book) == false)
        // Open, a moment unknown, open again.
        var open = UnfoldWatch()
        #expect(open.change(from: .flat, to: .unknown) == false)
        #expect(!open.mayBeOpening)
        #expect(open.change(from: .unknown, to: .book) == false)
        // Closed, unknown, closed again: no unfold, and nothing pending.
        var shut = UnfoldWatch()
        #expect(shut.change(from: .closed, to: .unknown) == false)
        #expect(shut.change(from: .unknown, to: .closed) == false)
        #expect(!shut.mayBeOpening)
        // An unknown reading never completes anything by itself.
        var any = UnfoldWatch()
        any.see(.closed)
        #expect(any.see(.unknown) == false)
    }

    @Test func openToOpenIsNotAnUnfold() {
        var watch = UnfoldWatch()
        #expect(watch.change(from: .closed, to: .book) == true)
        #expect(watch.change(from: .book, to: .flat) == false)
        #expect(watch.change(from: .flat, to: .laptop) == false)
    }

    @Test func aStaleMemoryIsCorrectedByTheOldPosture() {
        // The watch last saw closed, then missed readings (no multiview showing). A change from
        // flat to book is not an unfold.
        var watch = UnfoldWatch()
        watch.see(.closed)
        #expect(watch.change(from: .flat, to: .book) == false)
        // Missed an unknown after closed: closed is still the last known posture.
        var missed = UnfoldWatch()
        missed.see(.closed)
        #expect(missed.change(from: .unknown, to: .laptop) == true)
    }
}

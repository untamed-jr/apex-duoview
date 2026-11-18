import Testing
import Foundation
import Library
import LiveTiming
@testable import Multiview

@Suite struct CompanionSettingsTests {
    static func make() -> (CompanionSettings, MemoryStore) {
        let mem = MemoryStore()
        return (CompanionSettings(store: mem), mem)
    }

    @Test func defaults() {
        let (s, _) = Self.make()
        #expect(s.transcripts)
        #expect(s.autoPlayRadio)
        #expect(!s.hingeMixer)
        #expect(s.haptics)
        #expect(!s.showHapticsOnScreen)
        for kind in HapticKind.allCases { #expect(s.hapticOn(kind)) }
        for group in CardGroup.allCases { #expect(s.cardGroupOn(group)) }
        #expect(s.rewindSeconds == 5)
        #expect(s.lastClosedPage == .picture)
        #expect(s.scannerDriver == nil)
        #expect(s.gapPair == nil)
        #expect(s.radioFilter == .all)
        #expect(!s.closedHintShown)
    }

    @Test func roundTrip() {
        let (s, mem) = Self.make()
        s.transcripts = false
        s.autoPlayRadio = false
        s.hingeMixer = true
        s.haptics = false
        s.showHapticsOnScreen = true
        s.setHaptic(.red, on: false)
        s.setCardGroup(.flags, on: false)
        s.rewindSeconds = 15
        s.lastClosedPage = .gap
        s.scannerDriver = "44"
        s.gapPair = ["1", "16"]
        s.radioFilter = .driver("4")
        s.closedHintShown = true

        let t = CompanionSettings(store: mem)
        #expect(!t.transcripts)
        #expect(!t.autoPlayRadio)
        #expect(t.hingeMixer)
        #expect(!t.haptics)
        #expect(t.showHapticsOnScreen)
        #expect(!t.hapticOn(.red))
        #expect(t.hapticOn(.yellow))
        #expect(!t.cardGroupOn(.flags))
        #expect(t.cardGroupOn(.chequered))
        #expect(t.rewindSeconds == 15)
        #expect(t.lastClosedPage == .gap)
        #expect(t.scannerDriver == "44")
        #expect(t.gapPair == ["1", "16"])
        #expect(t.radioFilter == .driver("4"))
        #expect(t.closedHintShown)

        t.radioFilter = .myDriver
        #expect(CompanionSettings(store: mem).radioFilter == .myDriver)
        t.scannerDriver = nil
        t.gapPair = nil
        #expect(CompanionSettings(store: mem).scannerDriver == nil)
        #expect(CompanionSettings(store: mem).gapPair == nil)
        t.setHaptic(.red, on: true)
        #expect(t.hapticOn(.red))
    }

    @Test func eachHapticIsIndependent() {
        let (s, _) = Self.make()
        for kind in HapticKind.allCases {
            s.setHaptic(kind, on: false)
            for other in HapticKind.allCases { #expect(s.hapticOn(other) == (other != kind)) }
            s.setHaptic(kind, on: true)
        }
    }

    @Test func rewindOnlyAllowedValues() {
        let (s, _) = Self.make()
        for v in [3, 5, 10, 15] { s.rewindSeconds = v; #expect(s.rewindSeconds == v) }
        s.rewindSeconds = 15
        s.rewindSeconds = 7
        #expect(s.rewindSeconds == 5)
        s.rewindSeconds = -3
        #expect(s.rewindSeconds == 5)
    }

    @Test func corruptFallsBack() {
        let (s, mem) = Self.make()
        let junk = Data("not json".utf8)
        for key in ["transcripts", "autoPlayRadio", "hingeMixer", "haptics", "showHapticsOnScreen",
                    "rewindSeconds", "lastClosedPage", "scannerDriver", "gapPair", "radioFilter",
                    "closedHintShown", "haptic.red", "cardGroup.flags"] {
            mem.set(junk, forKey: "companion." + key)
        }
        #expect(s.transcripts)
        #expect(s.autoPlayRadio)
        #expect(!s.hingeMixer)
        #expect(s.haptics)
        #expect(!s.showHapticsOnScreen)
        #expect(s.rewindSeconds == 5)
        #expect(s.lastClosedPage == .picture)
        #expect(s.scannerDriver == nil)
        #expect(s.gapPair == nil)
        #expect(s.radioFilter == .all)
        #expect(!s.closedHintShown)
        #expect(s.hapticOn(.red))
        #expect(s.cardGroupOn(.flags))
    }

    @Test func wellFormedButWrongValuesFallBack() {
        let (s, mem) = Self.make()
        mem.set(Data(#""sideways""#.utf8), forKey: "companion.lastClosedPage")
        mem.set(Data("7".utf8), forKey: "companion.rewindSeconds")
        mem.set(Data(#"{"nope":{}}"#.utf8), forKey: "companion.radioFilter")
        mem.set(Data(#"["1"]"#.utf8), forKey: "companion.gapPair")
        #expect(s.lastClosedPage == .picture)
        #expect(s.rewindSeconds == 5)
        #expect(s.radioFilter == .all)
        #expect(s.gapPair == nil)
        mem.set(Data(#"["1","2","3"]"#.utf8), forKey: "companion.gapPair")
        #expect(s.gapPair == nil)
    }

    @Test func gapPairNeedsTwoDistinctNumbers() {
        let (s, _) = Self.make()
        s.gapPair = ["1"]
        #expect(s.gapPair == nil)
        s.gapPair = ["1", "1"]
        #expect(s.gapPair == nil)
        s.gapPair = ["1", "4"]
        #expect(s.gapPair == ["1", "4"])
        s.gapPair = ["1", "4", "9"]
        #expect(s.gapPair == ["1", "4"])
    }

    @Test func cardGroupOfEachKind() {
        #expect(CardGroup.of(.yellow) == .flags)
        #expect(CardGroup.of(.safetyCar) == .flags)
        #expect(CardGroup.of(.vsc) == .flags)
        #expect(CardGroup.of(.red) == .flags)
        #expect(CardGroup.of(.pit(car: "1")) == .myStopsAndRadio)
        #expect(CardGroup.of(.radio(car: "1", path: "TeamRadio/A_1_20261108_140000.mp3")) == .myStopsAndRadio)
        #expect(CardGroup.of(.out(car: "1")) == .myStopsAndRadio)
        #expect(CardGroup.of(.passed(car: "1", other: "2", position: 3)) == .myPositions)
        #expect(CardGroup.of(.chequered) == .chequered)
        #expect(CardGroup.of(.purpleSector(car: "1")) == nil)
    }

    @Test func keysArePrefixed() {
        let (s, mem) = Self.make()
        s.hingeMixer = true
        s.setHaptic(.purpleSector, on: false)
        #expect(mem.data(forKey: "companion.hingeMixer") != nil)
        #expect(mem.data(forKey: "companion.haptic.purpleSector") != nil)
    }
}

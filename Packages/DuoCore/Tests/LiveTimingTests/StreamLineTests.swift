import Testing
import Foundation
import F1TV
@testable import LiveTiming

@Suite struct StreamLineTests {
    @Test func parsesOffsetAndJSON() throws {
        let line = try #require(StreamLine.parse("00:01:02.345{\"a\":1}"))
        #expect(line.offsetMs == 62_345)
        #expect(line.json["a"].int == 1)
    }

    @Test func parsesHours() throws {
        let line = try #require(StreamLine.parse("01:00:00.000{\"a\":1}"))
        #expect(line.offsetMs == 3_600_000)
    }

    @Test func bomPrefixedFileGivesAllLines() {
        let text = "\u{FEFF}00:00:01.000{\"a\":1}\n00:00:02.000{\"a\":2}\r\n00:00:03.000{\"a\":3}\n"
        let lines = StreamLine.parseFile(Data(text.utf8))
        #expect(lines.map(\.offsetMs) == [1000, 2000, 3000])
    }

    @Test func truncatedAndBlankLinesAreSkipped() {
        let text = "00:00:01.000{\"a\":1}\n\n00:00:02.000{\"a\"\n00:00:03.000{\"a\":3}\ngarbage\n00:00:04.000{\"a\":4}\n00:00:05.000{\"a\""
        let lines = StreamLine.parseFile(Data(text.utf8))
        #expect(lines.map(\.offsetMs) == [1000, 3000, 4000])
    }

    @Test func truncatedLineIsNil() {
        #expect(StreamLine.parse("00:00:01.000{\"a\"") == nil)
        #expect(StreamLine.parse("00:00:01.000") == nil)
    }

    @Test func stringPayloadStaysString() throws {
        let line = try #require(StreamLine.parse("01:00:00.000\"eJw=\""))
        #expect(line.offsetMs == 3_600_000)
        #expect(line.json == .string("eJw="))
    }
}

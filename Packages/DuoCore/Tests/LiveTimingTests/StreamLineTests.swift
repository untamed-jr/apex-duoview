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

    @Test func onlyLineFeedEndsALine() throws {
        // U+2028, U+2029 and U+0085 can sit inside a JSON string; only "\n" (with an optional
        // "\r" before it) ends a line.
        let text = "00:00:01.000{\"a\":\"x\u{2028}y\u{2029}z\u{0085}w\"}\r\n00:00:02.000{\"a\":2}"
        let lines = StreamLine.parseFile(Data(text.utf8))
        #expect(lines.map(\.offsetMs) == [1000, 2000])
        #expect(lines.first?.json["a"].string == "x\u{2028}y\u{2029}z\u{0085}w")
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

    /// Past a day F1's recorder writes "d.HH:MM:SS.mmm" (the 2026 Mexico race's radio was all
    /// "1.02:32:50.914"); those lines and the plain ones around them all parse.
    @Test func dayPrefixedOffsets() throws {
        let text = "23:59:59.999{\"a\":1}\n1.00:00:00.000{\"a\":2}\n1.02:32:50.914{\"a\":3}\n12.01:00:00.001\"eJw=\"\n"
        let lines = StreamLine.parseFile(Data(text.utf8))
        #expect(lines.map(\.offsetMs) == [86_399_999, 86_400_000, 95_570_914, 1_040_400_001])
        #expect(lines.map { $0.json["a"].int } == [1, 2, 3, nil])
        #expect(lines.last?.json == .string("eJw="))
    }

    @Test func badDayPrefixesAreSkipped() {
        #expect(StreamLine.parse(".00:00:01.000{\"a\":1}") == nil)
        #expect(StreamLine.parse("x.00:00:01.000{\"a\":1}") == nil)
        #expect(StreamLine.parse("1x00:00:01.000{\"a\":1}") == nil)
        // More day digits than any recording could need: skipped, never an overflow trap.
        #expect(StreamLine.parse("99999999999999999999.00:00:01.000{\"a\":1}") == nil)
        #expect(StreamLine.parse("1.0:00:01.000{\"a\":1}") == nil)
    }
}

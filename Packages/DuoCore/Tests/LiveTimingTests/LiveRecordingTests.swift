import Foundation
import Testing
import F1TV
@testable import LiveTiming

struct LiveRecordingTests {
    static let racePath = "2026/2026-11-08_São_Paulo_Grand_Prix/2026-11-08_Race/"

    func message(_ topic: String, _ utc: UTCms, _ json: String, opening: Bool = false) throws -> RecordedMessage {
        RecordedMessage(topic: topic, utc: utc, opening: opening, json: try JSONValue.parse(Data(json.utf8)))
    }

    func file(_ path: String, _ messages: [RecordedMessage]) -> Data {
        Data((LiveRecording.header(sessionPath: path) + LiveRecording.lines(messages)).utf8)
    }

    @Test func recordingRoundTrip() throws {
        // Every committed fixture line, as recorded messages.
        var messages: [RecordedMessage] = []
        for session in ["sp26-race", "sp26-quali"] {
            let dir = try Fixture.url(session)
            let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".jsonStream") }.sorted()
            for name in names {
                let topic = String(name.dropLast(".jsonStream".count))
                for (i, line) in try Fixture.lines("\(session)/\(name)").enumerated() {
                    messages.append(RecordedMessage(topic: topic, utc: Fixture.raceStart + line.offsetMs, opening: i == 0, json: line.json))
                }
            }
        }
        let recorded = messages.filter { LiveRecording.records($0.topic) }
        #expect(recorded.count > 10_000)
        let back = LiveRecording.read(file(Self.racePath, messages))
        #expect(back.sessionPath == Self.racePath)
        #expect(back.messages.count == recorded.count)
        #expect(back.messages == recorded)

        // Text and numbers the format must carry through.
        let awkward = try [
            message("RaceControlMessages", 1, #"{"Messages":[{"Message":"TAB\tNEWLINE\nCR\rQUOTE\" SLASH\\ BELL\u0007 LS\u2028 São é 🏁"}]}"#),
            message("WeatherData", 2, #"{"AirTemp":"21.4","n":[0.1,-3.5,1e-7,1.5e300,-0.0,9007199254740993,123456789012,0,-17]}"#),
            message("TimingData", 3, #"{"Lines":{"1":{"InPit":true,"PitOut":false,"x":null,"Sectors":[{},[]]}}}"#, opening: true),
            message("Position.z", 4, #""tZg9bxxHDIb/y9Z3Bj+GQ871rhPA""#),
            message("LapCount", -5, #"7"#),
        ]
        let text = LiveRecording.lines(awkward)
        #expect(text.split(separator: "\n", omittingEmptySubsequences: false).count == awkward.count + 1)
        #expect(LiveRecording.read(file(Self.racePath, awkward)).messages == awkward)
        #expect(LiveRecording.line(awkward[3]) == "Position.z\t4\t0\t\"tZg9bxxHDIb/y9Z3Bj+GQ871rhPA\"\n")
        #expect(LiveRecording.line(awkward[2]).hasPrefix("TimingData\t3\t1\t{\"Lines\":"))
    }

    @Test func recordingWritesSortedCompactJSON() throws {
        let m = try message("SessionStatus", 1_794_157_403_965, #"{"Status":"Started", "Started":"Started", "n": 2.5}"#)
        #expect(LiveRecording.line(m) == "SessionStatus\t1794157403965\t0\t{\"Started\":\"Started\",\"Status\":\"Started\",\"n\":2.5}\n")
        #expect(JSONText.string(.number(.nan)) == "null")
        #expect(JSONText.string(.number(.infinity)) == "null")
        #expect(JSONText.string(.string("\u{1F}")) == "\"\\u001f\"")
    }

    @Test func recordingExcludesCarDataAndHeartbeat() throws {
        let car = try message("CarData.z", 1, #""7ZnBbtswDIbfxeduEElJlHLeZVhv2y5DUQyBk7ZB0yRIsmFD0XefbMeJFUsoHMDDBvRG""#)
        let beat = try message("Heartbeat", 2, #"{"Utc":"2026-11-08T17:03:23.965Z"}"#)
        let timing = try message("TimingData", 3, #"{"Lines":{"1":{"NumberOfLaps":3}}}"#)
        #expect(LiveRecording.excluded == ["CarData.z", "Heartbeat"])
        #expect(LiveRecording.line(car).isEmpty)
        #expect(LiveRecording.line(beat).isEmpty)
        #expect(LiveRecording.lines([car, beat, timing]) == LiveRecording.line(timing))
        #expect(LiveRecording.read(file(Self.racePath, [car, beat, timing])).messages == [timing])
        // A topic name the format can't hold is never written.
        #expect(LiveRecording.line(try message("Bad\tTopic", 4, "{}")).isEmpty)
        #expect(LiveRecording.line(try message("", 4, "{}")).isEmpty)
    }

    @Test func recordingAppendsAfterReopen() throws {
        let first = try [message("SessionInfo", 10, #"{"Path":"\#(Self.racePath)"}"#, opening: true),
                         message("TimingData", 11, #"{"Lines":{"1":{"NumberOfLaps":1}}}"#)]
        var data = file(Self.racePath, first)
        // Reopened for the same session: appended to, with no second header.
        #expect(LiveRecording.start(existingHead: data.prefix(4096), sessionPath: Self.racePath) == .append(prefix: "\n"))
        let second = try [message("TimingData", 20, #"{"Lines":{"1":{"NumberOfLaps":2}}}"#, opening: true)]
        data.append(Data(("\n" + LiveRecording.lines(second)).utf8))
        let back = LiveRecording.read(data)
        #expect(back.sessionPath == Self.racePath)
        #expect(back.messages == first + second)
        #expect(String(decoding: data, as: UTF8.self).components(separatedBy: "#session").count == 2)
    }

    @Test func appendAfterATornLine() throws {
        let kept = try message("TimingData", 11, #"{"Lines":{"1":{"NumberOfLaps":1}}}"#)
        let torn = try message("TimingData", 12, #"{"Lines":{"1":{"NumberOfLaps":2}}}"#)
        // The app was killed mid-write: the last line has no line break.
        var data = file(Self.racePath, [kept])
        data.append(Data(LiveRecording.line(torn).prefix(25).utf8))
        guard case .append(let prefix) = LiveRecording.start(existingHead: data, sessionPath: Self.racePath) else {
            Issue.record("expected to append")
            return
        }
        let next = try [message("TimingData", 20, #"{"Lines":{"1":{"NumberOfLaps":3}}}"#, opening: true),
                        message("LapCount", 21, #"{"CurrentLap":3}"#)]
        data.append(Data((prefix + LiveRecording.lines(next)).utf8))
        let back = LiveRecording.read(data)
        #expect(back.sessionPath == Self.racePath)
        #expect(back.messages == [kept] + next)
        // After a whole file it costs only an empty line.
        var whole = file(Self.racePath, [kept])
        whole.append(Data((prefix + LiveRecording.lines(next)).utf8))
        #expect(LiveRecording.read(whole).messages == [kept] + next)
    }

    @Test func newSessionStartsFresh() throws {
        let old = file(Self.racePath, try [message("TimingData", 1, #"{"Lines":{}}"#, opening: true)])
        let sprint = "2026/2026-11-08_São_Paulo_Grand_Prix/2026-11-07_Sprint/"
        #expect(LiveRecording.start(existingHead: old, sessionPath: sprint) == .fresh(header: "#session\t\(sprint)\n"))
        // No file yet, an empty one, or one cut before its header ends.
        #expect(LiveRecording.start(existingHead: nil, sessionPath: sprint) == .fresh(header: LiveRecording.header(sessionPath: sprint)))
        #expect(LiveRecording.start(existingHead: Data(), sessionPath: sprint) == .fresh(header: LiveRecording.header(sessionPath: sprint)))
        #expect(LiveRecording.start(existingHead: old.prefix(20), sessionPath: Self.racePath) != .append(prefix: "\n"))
        // A path that only starts the same is another session.
        #expect(LiveRecording.start(existingHead: old, sessionPath: String(Self.racePath.dropLast())) != .append(prefix: "\n"))
        #expect(LiveRecording.start(existingHead: file(String(Self.racePath.dropLast()), []), sessionPath: Self.racePath) != .append(prefix: "\n"))

        let fresh = try [message("SessionStatus", 2, #"{"Status":"Started"}"#, opening: true)]
        let back = LiveRecording.read(file(sprint, fresh))
        #expect(back.sessionPath == sprint)
        #expect(back.messages == fresh)
    }

    @Test func readSkipsWhatItCannotRead() throws {
        let good = try message("TrackStatus", 5, #"{"Status":"1","Message":"AllClear"}"#)
        let text = "TrackStatus\tnot-a-time\t0\t{}\n"
            + "TrackStatus\t5\t2\t{}\n"
            + "TrackStatus\t5\t0\t{not json\n"
            + "TrackStatus\t5\t0\n"
            + "\n"
            + LiveRecording.line(good)
            + "TrackStatus\t6\t0\t{\"Status\":\"2\"}"  // being written: no "\n" yet
        let back = LiveRecording.read(Data(text.utf8))
        #expect(back.sessionPath == nil)
        #expect(back.messages == [good])
        // A line ending in "\r\n" still reads.
        #expect(LiveRecording.read(Data((LiveRecording.line(good).dropLast() + "\r\n").utf8)).messages == [good])
        // Tabs and line breaks never reach the header.
        #expect(LiveRecording.header(sessionPath: "a\tb\nc/") == "#session\tabc/\n")
    }

    @Test func signalRMessagesBecomeRecordedMessages() throws {
        let state = try JSONValue.parse(Data(#"{"TimingData":{"Lines":{}},"DriverList":{"1":{"Tla":"VER"}}}"#.utf8))
        let opening = RecordedMessage.messages(from: .snapshot(invocationId: "0", state: state), receivedAt: 99)
        #expect(opening == [RecordedMessage(topic: "DriverList", utc: 99, opening: true, json: state["DriverList"]),
                            RecordedMessage(topic: "TimingData", utc: 99, opening: true, json: state["TimingData"])])
        let feed = RecordedMessage.messages(from: .feed(topic: "LapCount", data: .object(["CurrentLap": .number(4)]), utc: 7), receivedAt: 99)
        #expect(feed == [RecordedMessage(topic: "LapCount", utc: 7, opening: false, json: .object(["CurrentLap": .number(4)]))])
        #expect(RecordedMessage.messages(from: .ping, receivedAt: 1).isEmpty)
        #expect(RecordedMessage.messages(from: .snapshot(invocationId: "0", state: .null), receivedAt: 1).isEmpty)
    }
}

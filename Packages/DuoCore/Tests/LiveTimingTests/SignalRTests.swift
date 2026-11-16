import Testing
import Foundation
import F1TV
@testable import LiveTiming

private func json(_ s: String) -> JSONValue { try! JSONValue.parse(Data(s.utf8)) }

@Suite struct SignalRTests {
    @Test func framesSplitAndIgnoreTrailingPartial() {
        var data = Data()
        for part in [#"{"type":6}"#, #"{"type":7}"#, "not json"] {
            data.append(Data(part.utf8))
            data.append(0x1E)
        }
        data.append(Data(#"{"type":6"#.utf8))
        #expect(SignalR.frames(data) == [json(#"{"type":6}"#), json(#"{"type":7}"#)])
    }

    @Test func messageTypesDecode() {
        let feed = json(#"{"type":1,"target":"feed","arguments":["TrackStatus",{"Status":"1"},"2026-11-08T17:00:01.1234567Z"]}"#)
        #expect(SignalR.message(feed) == .feed(topic: "TrackStatus", data: json(#"{"Status":"1"}"#), utc: SignalR.utc("2026-11-08T17:00:01.123Z")!))
        #expect(SignalR.message(json(#"{"type":3,"invocationId":"1","result":{"A":{"b":1}}}"#))
                == .snapshot(invocationId: "1", state: json(#"{"A":{"b":1}}"#)))
        #expect(SignalR.message(json(#"{"type":6}"#)) == .ping)
        #expect(SignalR.message(json(#"{"type":7,"error":"bye"}"#)) == .close("bye"))
        #expect(SignalR.message(json(#"{"type":7}"#)) == .close(nil))
        #expect(SignalR.message(json(#"{"type":2}"#)) == .other)
        #expect(SignalR.message(json(#"{"type":1,"target":"other","arguments":[]}"#)) == .other)
    }

    @Test func utcParsesFractions() {
        // 2026-11-08T17:00:01Z
        let base: Int64 = 1_794_157_201_000
        #expect(SignalR.utc("2026-11-08T17:00:01Z") == base)
        #expect(SignalR.utc("2026-11-08T17:00:01.1234567Z") == base + 123)
        #expect(SignalR.utc("2026-11-08T17:00:01.5Z") == base + 500)
        #expect(SignalR.utc("1970-01-01T00:00:00.001Z") == 1)
        #expect(SignalR.utc("2026-11-08T17:00:01") == nil)
        #expect(SignalR.utc("garbage") == nil)
    }

    @Test func subscribeDecodesBackToFourteenTopics() throws {
        let data = SignalR.subscribe(invocationId: "1")
        #expect(data.last == 0x1E)
        let msg = try #require(SignalR.frames(data).first)
        #expect(msg["type"].int == 1)
        #expect(msg["invocationId"].string == "1")
        #expect(msg["target"].string == "Subscribe")
        let topics = msg["arguments"][0].array.map(\.string)
        #expect(topics.count == 14)
        #expect(topics == SignalR.topics)
        #expect(topics.first == "Heartbeat" && topics.last == "WeatherData")
    }

    @Test func handshakeAndPing() {
        #expect(SignalR.handshake() == Data(#"{"protocol":"json","version":1}"#.utf8) + [0x1E])
        #expect(SignalR.ping() == Data(#"{"type":6}"#.utf8) + [0x1E])
    }

    @Test func negotiateTokenPrefersConnectionToken() {
        #expect(SignalR.negotiateToken(json(#"{"connectionToken":"t","connectionId":"i"}"#)) == "t")
        #expect(SignalR.negotiateToken(json(#"{"connectionId":"i"}"#)) == "i")
        #expect(SignalR.negotiateToken(json(#"{}"#)) == nil)
    }
}

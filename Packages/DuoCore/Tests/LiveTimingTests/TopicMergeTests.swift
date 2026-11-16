import Testing
import Foundation
import F1TV
@testable import LiveTiming

private func json(_ s: String) -> JSONValue { try! JSONValue.parse(Data(s.utf8)) }

@Suite struct TopicMergeTests {
    @Test func mergeNestedObjects() {
        let out = TopicMerge.merge(json(#"{"Lines":{"1":{"Position":"3"}}}"#),
                                   json(#"{"Lines":{"1":{"InPit":true}}}"#))
        #expect(out == json(#"{"Lines":{"1":{"Position":"3","InPit":true}}}"#))
    }

    @Test func mergeKeyedDeltaIntoArray() {
        let out = TopicMerge.merge(json(#"{"Sectors":[{"Value":""},{"Value":""},{"Value":""}]}"#),
                                   json(#"{"Sectors":{"1":{"Value":"28.1"}}}"#))
        #expect(out == json(#"{"Sectors":[{"Value":""},{"Value":"28.1"},{"Value":""}]}"#))
    }

    @Test func deltaGrowsArray() {
        let out = TopicMerge.merge(json("[]"), json(#"{"2":{"a":1}}"#))
        #expect(out == json(#"[null,null,{"a":1}]"#))
    }

    @Test func scalarsAndArraysReplace() {
        #expect(TopicMerge.merge(json(#"{"a":"x","b":[1,2,3]}"#), json(#"{"a":"y","b":[9]}"#))
                == json(#"{"a":"y","b":[9]}"#))
    }

    @Test func keyframeMarkerIsDropped() {
        let out = TopicMerge.merge(json(#"{"a":1}"#), json(#"{"_kf":true,"b":2}"#))
        #expect(out == json(#"{"a":1,"b":2}"#))
    }

    @Test func deletedRemovesListedKeys() {
        let out = TopicMerge.merge(json(#"{"Lines":{"1":{},"2":{},"3":{}}}"#),
                                   json(#"{"Lines":{"_deleted":["2"]}}"#))
        #expect(out == json(#"{"Lines":{"1":{},"3":{}}}"#))
    }

    @Test func newKeyedObjectFromNothingStaysObject() {
        let out = TopicMerge.merge(.null, json(#"{"Lines":{"1":{"a":1}}}"#))
        #expect(out == json(#"{"Lines":{"1":{"a":1}}}"#))
    }

    @Test func reconnectSnapshotReplaces() {
        var state = TopicState()
        state.apply(snapshot: json(#"{"TimingData":{"Lines":{"1":{"Position":"1"},"2":{"Position":"2"}}},"LapCount":{"CurrentLap":3}}"#))
        state.apply(topic: "TimingData", delta: json(#"{"Lines":{"3":{"Position":"3"}}}"#))
        #expect(state.topics["TimingData"]?["Lines"]["3"]["Position"].string == "3")
        state.apply(snapshot: json(#"{"TimingData":{"Lines":{"1":{"Position":"2"}}}}"#))
        #expect(state.topics["TimingData"] == json(#"{"Lines":{"1":{"Position":"2"}}}"#))
        // Topics a snapshot doesn't name are kept.
        #expect(state.topics["LapCount"]?["CurrentLap"].int == 3)
    }
}

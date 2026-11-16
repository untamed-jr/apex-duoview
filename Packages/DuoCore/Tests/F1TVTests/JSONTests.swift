import Foundation
import Testing
@testable import F1TV

@Suite struct JSONValueTests {
    static let v = try! JSONValue.parse(Data(#"{"a":"x","n":5,"s":"7","t":"true","f":false,"z":null,"arr":[1,"b"],"d":1.5}"#.utf8))

    @Test func lenientAccessors() {
        let v = Self.v
        #expect(v["a"].string == "x")
        #expect(v["n"].string == "5")
        #expect(v["d"].string == "1.5")
        #expect(v["z"].string == "")
        #expect(v["missing"].string == "")
        #expect(v["arr"].string == "")
        #expect(v["n"].int == 5)
        #expect(v["s"].int == 7)
        #expect(v["a"].int == nil)
        #expect(v["t"].bool == true)
        #expect(v["f"].bool == false)
        #expect(v["a"].bool == nil)
        #expect(v["arr"].array.count == 2)
        #expect(v["a"].array.isEmpty)
        #expect(v["arr"][1].string == "b")
        #expect(v["arr"][9] == .null)
        #expect(v["a"]["b"] == .null)
        #expect(v["a"][0] == .null)
    }

    /// JSON's true/false stay booleans and 1/0 stay numbers on every platform, whatever
    /// NSNumber does with them.
    @Test func booleansAndNumbersStayApart() throws {
        let v = try JSONValue.parse(Data("[true,false,1,0,1.0,-3,1.5e3]".utf8))
        #expect(v == .array([.bool(true), .bool(false), .number(1), .number(0), .number(1), .number(-3), .number(1500)]))
        #expect(v == (try JSONValue.parseByDecoding(Data("[true,false,1,0,1.0,-3,1.5e3]".utf8))))
    }

    @Test func fragmentsParse() throws {
        #expect(try JSONValue.parse(Data(#""eJw=""#.utf8)) == .string("eJw="))
        #expect(try JSONValue.parse(Data("5".utf8)) == .number(5))
        #expect(try JSONValue.parse(Data("null".utf8)) == .null)
        #expect(try JSONValue.parse(Data(" true ".utf8)) == .bool(true))
    }

    @Test func nestedValuesMatchTheDecoder() throws {
        let text = #"{"a":{"b":[null,{"c":"\u00e9\ud83c\udfc1"}],"d":-0.25,"e":12345678901234567890},"f":"x\ny"}"#
        #expect(try JSONValue.parse(Data(text.utf8)) == (try JSONValue.parseByDecoding(Data(text.utf8))))
        #expect(try JSONValue.parse(Data(text.utf8))["a"]["b"][1]["c"].string == "é🏁")
    }

    @Test func malformedInputThrowsBothWays() {
        for text in ["", "{", "[1 2]", "{\"a\":1} x", "tru", "{\"a\" 1}"] {
            #expect(throws: (any Error).self, "\(text)") { try JSONValue.parse(Data(text.utf8)) }
            #expect(throws: (any Error).self, "\(text)") { try JSONValue.parseByDecoding(Data(text.utf8)) }
        }
    }
}

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

    /// Where `parse` (JSONSerialization) and the decoder it replaced are known to differ; none of
    /// it occurs in F1's data (JSONFastPathTests compares every committed fixture line). The exact
    /// values were measured on Linux; Apple's Foundation may differ, so those are Linux-only.
    @Test func knownDifferencesFromTheDecoder() throws {
        // Duplicate keys: the last wins (Linux, and expected of Apple's NSDictionary building;
        // not run there).
        let duplicate = Data(#"{"a":1,"a":2}"#.utf8)
        #expect(try JSONValue.parse(duplicate) == .object(["a": .number(2)]))
        #if os(Linux)
        #expect(try JSONValue.parseByDecoding(duplicate) == .object(["a": .number(1)]))  // the decoder keeps the first
        #endif

        // A literal that underflows reads as 0, where the decoder throws.
        #if os(Linux)
        #expect(try JSONValue.parse(Data("1e-400".utf8)) == .number(0))
        #expect(throws: (any Error).self) { try JSONValue.parseByDecoding(Data("1e-400".utf8)) }
        #endif

        // 17 or more significant digits can come out a few ulps off; the decoder rounds
        // correctly. Up to about 20 ulps were measured on Linux over random doubles.
        let text = "0.30000000000000004"
        let exact = try #require(Double(text))
        guard case .number(let fast) = try JSONValue.parse(Data(text.utf8)),
              case .number(let decoded) = try JSONValue.parseByDecoding(Data(text.utf8))
        else { Issue.record("not numbers"); return }
        #expect(decoded == exact)
        // Only the bound: the exact ulp (one up on today's Linux) is the parser's rounding, and a
        // toolchain that fixes it mustn't turn this red.
        #expect(abs(fast - exact) <= 32 * exact.ulp)
        // With 16 digits or fewer they agree (none of 100 000 random 16-digit doubles differed on
        // Linux; Apple's is not run here).
        for short in ["0.3000000000000000", "-1234.567", "2.146183727904518e-11", "42315.23049734208"] {
            #expect(try JSONValue.parse(Data(short.utf8)) == .number(Double(short)!), "\(short)")
        }
    }

    @Test func malformedInputThrowsBothWays() {
        for text in ["", "{", "[1 2]", "{\"a\":1} x", "tru", "{\"a\" 1}"] {
            #expect(throws: (any Error).self, "\(text)") { try JSONValue.parse(Data(text.utf8)) }
            #expect(throws: (any Error).self, "\(text)") { try JSONValue.parseByDecoding(Data(text.utf8)) }
        }
    }
}

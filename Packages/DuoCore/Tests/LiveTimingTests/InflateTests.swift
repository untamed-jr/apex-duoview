import Testing
import Foundation
import F1TV
@testable import LiveTiming

@Suite struct InflateTests {
    static func inflate(_ b64: String) throws -> [UInt8] {
        let data = try #require(Data(base64Encoded: b64))
        return [UInt8](try Inflate.raw(data))
    }

    /// Level 0 output of Python's zlib: stored blocks of at most 65535 bytes. Built here rather
    /// than embedded because incompressible data would add ~93 KB of base64.
    static func storedStream(_ payload: [UInt8]) -> Data {
        var out = Data()
        var rest = payload[...]
        repeat {
            let chunk = rest.prefix(65535)
            rest = rest.dropFirst(chunk.count)
            let len = UInt16(chunk.count)
            out.append(rest.isEmpty ? 1 : 0)
            out.append(contentsOf: [UInt8(len & 0xFF), UInt8(len >> 8), UInt8(~len & 0xFF), UInt8(~len >> 8)])
            out.append(contentsOf: chunk)
        } while !rest.isEmpty
        return out
    }

    @Test func emptyInput() throws {
        #expect(try Self.inflate("AwA=").isEmpty)
    }

    @Test func fixedHuffman() throws {
        #expect(try Self.inflate("y0jNyclXyECQAA==") == Array("hello hello hello".utf8))
    }

    @Test func storedBlocksSpanTwoBlocks() throws {
        let payload = (0..<70_000).map { UInt8(($0 * 7 + $0 / 251) % 256) }
        let stream = Self.storedStream(payload)
        #expect(stream.count == 70_000 + 10)
        #expect([UInt8](try Inflate.raw(stream)) == payload)
    }

    @Test func dynamicHuffman() throws {
        var text = ""
        var i = 0
        while text.utf8.count < 20_000 {
            text += "{\"RacingNumber\":\"\(i % 20 + 1)\",\"Line\":\((i * 7) % 20),"
            text += "\"Gap\":\"+\((i * 13) % 90).\(String(format: "%03d", (i * 37) % 1000))\",\"Name\":\"Driver\(i % 9)\"},"
            i += 1
        }
        let expected = Array(text.utf8.prefix(20_000))
        #expect(try Self.inflate("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") == expected)
    }

    @Test func backReferenceCrossesWindow() throws {
        let prefix = (0..<300).map { UInt8(truncatingIfNeeded: $0 * $0 * 31 + $0 / 3) }
        let expected = prefix + [UInt8](repeating: 0x78, count: 32_000) + prefix
        #expect(try Self.inflate("7d3bShMAAIDhUWsNs1pWarnQxkrtYq1lUiq2li1cIRaEMsU8RGbpChorygOKRJadTDoMHUVktBYhrlLymIYL1GzpUKIDU2EoXSioS9bqpgfwAf7vRT5BeHHotDhr+r0z3Gq83Jm0TKhpMxmeBDvejqf+/ikqCJhcnuv74knor7POlmoP3ZR86hOX71bkOCvOmoUvbtvX22teiiznr4zkx6irJK7Rjea0o9VLm23fDi9MrDKF+SPKpN41p/yf3aqOa7Vfs+VbTrjr7w3sn/OEVCo3qBuSt+meaaQ7r0p/+XTDloYpg3J7oefxg4F9M+7Vl+QrlLW71qlubPWvPentHYp4fs7UErcwr7LlpVf/sZk/KFzvvqt/tI7scFgal9QcP22PFwgP9FSUvFGMucQX5JI9j7TROutBWcLdKN/KzMnX7aLrKam3Ah1dXsPmIM0rfdKZQeMxo7NIm9WkDY00Cj4OBj/U6+8H9XV7CzcFxj1Nic1oz96b2XwkKvGObOav7iIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/Cfgil/0Ff8P") == expected)
    }

    @Test func corruptInputThrows() {
        #expect(throws: InflateError.corrupt) { try Inflate.raw(Data([0xFF, 0xFF])) }
    }

    @Test func truncatedInputThrows() throws {
        let full = try #require(Data(base64Encoded: "pZrNipzJEUXfpbYWScZvRs7a4I2Zhd9ANsJoMYMR2JvB7+5Y1WeKK7gQ24ZUCyk4p/vW+eP1t6//+P77P3/9929///bj9ctLXl9ef/3++7fXL/vL6y9f/9Vf+tNee+/++q9ff+uvv/784/t/vv3Yr/9++ePztb5fn/drsbXtfD4X9Nzez8Xf7zXXPv75XtF7f96/n9tdIvL53NDzeD+v9/PQJV6fzx09z+e7x/t9xpKKz/eB3p/3e30/P7VU9fN5ouf1fn6ff/ulcT9fH/T6Pn/5fJ770puf7wu9l/3+A+z5rzvLzKjLkefw5Lk838vOpm5HntuT5/jClu9DHY881/ccX+Zyd+p65P+u7zm/c5eXUPcjz/3Jc4C6Qoq6H3kO8Lk/iRUR1AHJc4DyXKDWiqvUDclzgvLcoMtKvdwRPVf4HGH4ykwOP88RynOFedbZxh0RoF/tdXxTJ4TwZ+ucQx0QpJ/kKnHqfhD99K4Koc4H0c91VRV1PZB+EetqUMeD6Je1bip1Ooh+JeveS10OxJ+3uJK7G0Q/OS0u49gD6We71bU5+ED6ubW8DgcfRL/Ilpdz8IH0y9v6Eo4+kH6lbbDi6IPwFy2w4NgD6SfVBlPOYJB+JsvyckeE6OfeAkuOPpB+cdpgxh0RoN/Z7a9NnRCiX1nr61AXBPGXbS+n7gfRT267S6jrQfQzbXMVdT2Qfh5trqCOB9Evqr2l1Okg+h1Zxy51OZB+5W2u5A4H4e+0uIxjD6Sf7lbX5uAD6WfW8jocfBD9PFtezrEH0i9u60s4+kD6HW2BFUcfRL+KNlhw8IH4qzaYcgaD9FNZsi93Q4h+5i2w5OgD6eenDWbcEQH65W5/beqEEP2Otb0OdUGQfpWtL6cOCOHvtruEuh5EP9U2V1HHA+ln0eYK6ngQ/bzaW0qdDqJfyvJzqcuB9Dve4krucBD96rS5jIMPxJ/sdtfm6APxp9b2Ohx9EP4s217OwQfiz2/7Szj6QPyltsGKww/C34k2WHD0wfirdphyDoP8E1nll7sixD/1Vlhy/IH8s9MOM+6KAP9it8E2dUOIf2ntr0OdEOTfyfaXUxeE+Fe39SXU/SAAira8ijofCECNlldQ14MAaNXqUup2EABDlsqlTgcCML3dldzlwB//TrvLOPxAAO62F7c6Y/6Jtb+43RnyT7P9xe3OmH9222Dc8oz5F9oO47ZnyL+Mdhi3PWP+nWqJcevzT/i3orj9GeJPvBXG7c8Yf3raYeQADfDnuw3Gzc8If2HtL258xr/8ZvuLG58R/s5te3HTM/z5r9XFDc+QfhKtLm54RvTTanFxszOin8u6wY3OkH7hbS5udIb0y9PmIjdnSL/a7S5udf7Jb78tL253hvSTbHlxuzOmn97WF7c8Y/q5tsC47RlPf9EC47ZnTL+sNhi3PmP6lSxTbn/G218LjNufMf3ktMHIARrQz3b7i5ufEf3c2l7c+AzpF9n24sZnRL+87S5uekb0K211ccMz/uSjzcUNz4h+Uu0tbnZG9DNZebnRGX/w4S0ubnSG9IvT4iI3Z0i/s1td3OqM6VfW9uJ2Z/y5b8uL250x/eS2vrjlGdPPtAXGbc+Qfh4tMG57xvSLaoNx6zOm35G1k9ufIf3K22Dc/ozxd9pg5AAN6Ke7/cXNz/BjX2t7ceMzpJ9n24sbnxH94ra7uOkZ0e9om4sbniH9Klpd3PCM8FftLW52RvRTWW7c6AzpZ97i4kZnSD8/LS5yc4b0y93q4lZnTL9jLS9ud4b0q2x7cbszxt9tfXHL80+iF22BcdszpJ9FC4zbnjH9vNpg3PqM6ZeyanP7M6Tf8RYYtz9j+tVphZEDNMCf7BYYNz8j/Km1vrjxGeLPsvXFjc8If35bXtz0jPCX2urihmeIvxOtLm54hvirNhc3O8PoT5YcbnSG/FNvdXGjM+SfnVYXuTlD/sVueXGrM+ZfWuuL250h/062vrjdGfOvbhuMW54xAEXbYdz2DAGo0Q7jtmcMQKuWGLc+YwCGrHBuf4YATG+HcfvzT378Oy0xcoCG0XPmKHrOO4uej42i53NG0XPtWfRcPoqeqybR85VZ9HxjFj3fO4yetw2j552z6Fn2MHoWn0XPcmbRs8owetYYRs9as+jZdBg9W46iZ9+T6NltFj37GUXPIaPoOXwWPUeNoufUUfScMYqe886i52PD6PmcYfRcexY9lw+j56ph9HxlFD3fGEbP9w6j562z6HnnMHqWPYqexUfRs5xR9Kwyip41RtGz1ix6Nh1Fz5aj6NnuLHp2G0XPfobRc8gweg6fRc9Rw+g5dRg9Z8yi57yz6PnYMHo+OYueaw+j5/JR9Fw1ip6vzKLnG5Po+d5R9Lx1Fj3vHEXPskfRs9gsepYzi55VhtGzxjB61ppFz6bD6NlyGD3bnUXPbsPo2c8weo49i57Dh9Fz1Ch6Th1Fzxmz6DnvKHo+NoqeT86i59qj6Ll8FD3XmUXPV2bR841Z9HzvMHreOouedw6jZ9nD6FlsFj3LGUbPKrPoWX0WPWsNo2fTUfRsOYqe7c6iZ7dR9OxnEj3HnkXP4aPoOWoUPafMoueMWfScdxg9H5tFzydn0XPtYfRcPoye68yi5yvD6PnGMHq+NYqetw6j552j6Fn2KHoWm0XPckbRs8ooelYfRc9ao+jZdBQ9W8yiZ7uz6NltGD37GUbPsUfRc3x+8PE/"))
        #expect(throws: InflateError.corrupt) { try Inflate.raw(full.prefix(full.count / 2)) }
        #expect(throws: InflateError.corrupt) { try Inflate.raw(Data()) }
    }

    @Test func zPayloadDecodesJSON() throws {
        let json = try ZPayload.decode("q1YKyC/OLMnMz1Oyio6tBQA=")
        #expect(json == .object(["Position": .array([])]))
    }

    @Test func zPayloadRejectsBadBase64() {
        #expect(throws: ZPayloadError.badBase64) { try ZPayload.decode("!!!") }
    }

    @Test func realPositionLine() throws {
        let dir = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let line = try String(contentsOf: dir.appendingPathComponent("Position.z.line.txt"), encoding: .utf8)
        let expected = try Data(contentsOf: dir.appendingPathComponent("Position.z.expected.json"))
        let parsed = try #require(StreamLine.parse(line.trimmingCharacters(in: .whitespacesAndNewlines)[...]))
        #expect(parsed.offsetMs == 2850)
        guard case .string(let payload) = parsed.json else { Issue.record("not a string payload"); return }
        #expect(try ZPayload.decode(payload) == (try JSONValue.parse(expected)))
    }

    /// A literal-only fixed-Huffman stream: the slowest shape for the symbol decoder.
    static func fixedLiteralStream(_ payload: [UInt8]) -> Data {
        var out = [UInt8]()
        var acc: UInt32 = 0
        var n = 0
        func put(_ value: UInt32, _ count: Int, msbFirst: Bool) {
            for k in 0..<count {
                let bit = msbFirst ? (value >> UInt32(count - 1 - k)) & 1 : (value >> UInt32(k)) & 1
                acc |= bit << UInt32(n)
                n += 1
                if n == 8 { out.append(UInt8(acc)); acc = 0; n = 0 }
            }
        }
        put(1, 1, msbFirst: false)  // final
        put(1, 2, msbFirst: false)  // fixed Huffman
        for b in payload { put(0x30 + UInt32(b), 8, msbFirst: true) }  // literals 0...143
        put(0, 7, msbFirst: true)   // end of block
        if n > 0 { out.append(UInt8(acc)) }
        return Data(out)
    }

    @Test func inflatesOneMegabyteQuickly() throws {
        var payload = [UInt8]()
        payload.reserveCapacity(1_048_576)
        var x: UInt32 = 12345
        while payload.count < 1_048_576 {
            x = x &* 1_103_515_245 &+ 12_345
            payload.append(UInt8(truncatingIfNeeded: 48 + (x >> 16) % 10))
        }
        let packed = Self.fixedLiteralStream(payload)
        let start = Date()
        let out = try Inflate.raw(packed)
        let elapsed = Date().timeIntervalSince(start)
        #expect([UInt8](out) == payload)
        #expect(elapsed < 2)
    }
}

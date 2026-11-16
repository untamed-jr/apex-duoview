import Foundation

public enum InflateError: Error, Equatable {
    case corrupt
}

/// RFC 1951 raw deflate (stored, fixed and dynamic blocks), for the `.z` payloads of the
/// live timing feed. Never traps on bad input: anything malformed throws `.corrupt`.
public enum Inflate {
    public static func raw(_ data: Data) throws -> Data {
        var decoder = Decoder(input: [UInt8](data))
        return Data(try decoder.run())
    }

    // MARK: Huffman

    private static let fastBits = 10

    private struct Huffman: Sendable {
        var counts = [UInt16](repeating: 0, count: 16)
        var symbols: [UInt16]
        /// symbol << 4 | length, or 0 when the code is longer than `fastBits`.
        var fast = [UInt16](repeating: 0, count: 1 << Inflate.fastBits)

        init(lengths: [UInt8]) throws {
            symbols = [UInt16](repeating: 0, count: lengths.count)
            for l in lengths { counts[Int(l)] += 1 }
            counts[0] = 0
            var left = 1
            for len in 1...15 {
                left <<= 1
                left -= Int(counts[len])
                if left < 0 { throw InflateError.corrupt }  // oversubscribed
            }
            var offsets = [Int](repeating: 0, count: 16)
            for len in 1..<15 { offsets[len + 1] = offsets[len] + Int(counts[len]) }
            var nextCode = [Int](repeating: 0, count: 16)
            var code = 0
            for len in 1...15 {
                code = (code + Int(counts[len - 1])) << 1
                nextCode[len] = code
            }
            for (sym, l) in lengths.enumerated() where l != 0 {
                let len = Int(l)
                symbols[offsets[len]] = UInt16(sym)
                offsets[len] += 1
                let c = nextCode[len]
                nextCode[len] += 1
                if len <= Inflate.fastBits {
                    var rev = 0
                    for i in 0..<len where c & (1 << i) != 0 { rev |= 1 << (len - 1 - i) }
                    let entry = UInt16(sym << 4 | len)
                    var idx = rev
                    while idx < fast.count {
                        fast[idx] = entry
                        idx += 1 << len
                    }
                }
            }
        }
    }

    // MARK: Decoder

    private static let lengthBase: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
                                            35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
                                             3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distBase: [Int] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
                                          257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
                                          8193, 12289, 16385, 24577]
    private static let distExtra: [Int] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
                                           7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    private static let clOrder: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private static let fixedTables: (lit: Huffman, dist: Huffman)? = {
        var l = [UInt8](repeating: 8, count: 288)
        for i in 144..<256 { l[i] = 9 }
        for i in 256..<280 { l[i] = 7 }
        guard let lit = try? Huffman(lengths: l),
              let dist = try? Huffman(lengths: [UInt8](repeating: 5, count: 30)) else { return nil }
        return (lit, dist)
    }()

    private struct Decoder {
        let input: [UInt8]
        var pos = 0
        var bitBuf: UInt64 = 0
        var bitCnt = 0
        /// The whole output is kept, so back-references can reach the full 32 KB window.
        var out: [UInt8] = []

        init(input: [UInt8]) { self.input = input }

        mutating func refill() {
            while bitCnt <= 56, pos < input.count {
                bitBuf |= UInt64(input[pos]) << UInt64(bitCnt)
                pos += 1
                bitCnt += 8
            }
        }

        mutating func bits(_ n: Int) throws -> Int {
            if n == 0 { return 0 }
            if bitCnt < n {
                refill()
                if bitCnt < n { throw InflateError.corrupt }
            }
            let v = Int(bitBuf & ((1 << UInt64(n)) - 1))
            bitBuf >>= UInt64(n)
            bitCnt -= n
            return v
        }

        mutating func symbol(_ h: Huffman) throws -> Int {
            if bitCnt < 15 { refill() }
            let entry = h.fast[Int(bitBuf & UInt64(h.fast.count - 1))]
            if entry != 0 {
                let len = Int(entry & 15)
                if len > bitCnt { throw InflateError.corrupt }
                bitBuf >>= UInt64(len)
                bitCnt -= len
                return Int(entry >> 4)
            }
            var code = 0, first = 0, index = 0
            for len in 1...15 {
                if len > bitCnt { throw InflateError.corrupt }
                code |= Int((bitBuf >> UInt64(len - 1)) & 1)
                let count = Int(h.counts[len])
                if code - count < first {
                    bitBuf >>= UInt64(len)
                    bitCnt -= len
                    return Int(h.symbols[index + (code - first)])
                }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            throw InflateError.corrupt
        }

        mutating func run() throws -> [UInt8] {
            var final = false
            repeat {
                final = try bits(1) == 1
                switch try bits(2) {
                case 0: try stored()
                case 1:
                    guard let fixed = Inflate.fixedTables else { throw InflateError.corrupt }
                    try compressed(fixed.lit, fixed.dist)
                case 2:
                    let (lit, dist) = try dynamicTables()
                    try compressed(lit, dist)
                default: throw InflateError.corrupt
                }
            } while !final
            return out
        }

        mutating func stored() throws {
            // Drop the partial byte, then hand back whole bytes the refill read ahead.
            let drop = bitCnt % 8
            bitBuf >>= UInt64(drop)
            bitCnt -= drop
            pos -= bitCnt / 8
            bitBuf = 0
            bitCnt = 0
            guard pos + 4 <= input.count else { throw InflateError.corrupt }
            let len = Int(input[pos]) | Int(input[pos + 1]) << 8
            let nlen = Int(input[pos + 2]) | Int(input[pos + 3]) << 8
            guard len == (~nlen & 0xFFFF) else { throw InflateError.corrupt }
            pos += 4
            guard pos + len <= input.count else { throw InflateError.corrupt }
            out.append(contentsOf: input[pos..<(pos + len)])
            pos += len
        }

        mutating func dynamicTables() throws -> (Huffman, Huffman) {
            let nlen = try bits(5) + 257
            let ndist = try bits(5) + 1
            let ncode = try bits(4) + 4
            guard nlen <= 286, ndist <= 30 else { throw InflateError.corrupt }
            var cl = [UInt8](repeating: 0, count: 19)
            for i in 0..<ncode { cl[Inflate.clOrder[i]] = UInt8(try bits(3)) }
            let clHuff = try Huffman(lengths: cl)
            var lengths = [UInt8](repeating: 0, count: nlen + ndist)
            var i = 0
            while i < nlen + ndist {
                let sym = try symbol(clHuff)
                if sym < 16 {
                    lengths[i] = UInt8(sym)
                    i += 1
                } else {
                    var prev: UInt8 = 0
                    var repeatCount: Int
                    switch sym {
                    case 16:
                        guard i > 0 else { throw InflateError.corrupt }
                        prev = lengths[i - 1]
                        repeatCount = 3 + (try bits(2))
                    case 17: repeatCount = 3 + (try bits(3))
                    default: repeatCount = 11 + (try bits(7))
                    }
                    guard i + repeatCount <= nlen + ndist else { throw InflateError.corrupt }
                    while repeatCount > 0 {
                        lengths[i] = prev
                        i += 1
                        repeatCount -= 1
                    }
                }
            }
            guard lengths[256] != 0 else { throw InflateError.corrupt }
            return (try Huffman(lengths: Array(lengths[0..<nlen])),
                    try Huffman(lengths: Array(lengths[nlen...])))
        }

        mutating func compressed(_ lit: Huffman, _ dist: Huffman) throws {
            while true {
                let sym = try symbol(lit)
                if sym < 256 {
                    out.append(UInt8(sym))
                } else if sym == 256 {
                    return
                } else {
                    let li = sym - 257
                    guard li < 29 else { throw InflateError.corrupt }
                    let len = Inflate.lengthBase[li] + (try bits(Inflate.lengthExtra[li]))
                    let di = try symbol(dist)
                    guard di < 30 else { throw InflateError.corrupt }
                    let d = Inflate.distBase[di] + (try bits(Inflate.distExtra[di]))
                    guard d <= out.count else { throw InflateError.corrupt }
                    var src = out.count - d
                    for _ in 0..<len {
                        out.append(out[src])
                        src += 1
                    }
                }
            }
        }
    }
}

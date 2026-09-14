//
//  ByteReader.swift
//  BinaryExplorer
//
//  Bounds-checked cursor over a Data buffer. Every parser in Core reads through
//  this so that a malformed IPA produces nil instead of a crash.
//

import Foundation

struct ByteReader {
    let data: Data
    private(set) var offset: Int

    init(_ data: Data, offset: Int = 0) {
        self.data = data
        self.offset = offset
    }

    var count: Int { data.count }
    var remaining: Int { max(0, data.count - offset) }

    mutating func seek(to newOffset: Int) {
        offset = newOffset
    }

    mutating func skip(_ n: Int) {
        offset += n
    }

    func canRead(_ n: Int, at pos: Int? = nil) -> Bool {
        let start = pos ?? offset
        guard start >= 0, n >= 0 else { return false }
        return start &+ n <= data.count
    }

    /// Reads a fixed-width unsigned integer, honouring the requested endianness.
    mutating func read<T: FixedWidthInteger & UnsignedInteger>(_ type: T.Type, bigEndian: Bool = false) -> T? {
        let size = MemoryLayout<T>.size
        guard canRead(size) else { return nil }
        var value: T = 0
        let start = data.startIndex + offset
        for i in 0..<size {
            value |= T(data[start + i]) << T(8 * i)
        }
        offset += size
        return bigEndian ? value.byteSwapped : value
    }

    mutating func u8() -> UInt8? { read(UInt8.self) }
    mutating func u16(_ big: Bool = false) -> UInt16? { read(UInt16.self, bigEndian: big) }
    mutating func u32(_ big: Bool = false) -> UInt32? { read(UInt32.self, bigEndian: big) }
    mutating func u64(_ big: Bool = false) -> UInt64? { read(UInt64.self, bigEndian: big) }

    mutating func bytes(_ n: Int) -> Data? {
        guard canRead(n) else { return nil }
        let start = data.startIndex + offset
        let slice = data[start..<(start + n)]
        offset += n
        return Data(slice)
    }

    /// Fixed-size character field (Mach-O segname / sectname), NUL-trimmed.
    mutating func fixedString(_ n: Int) -> String? {
        guard let raw = bytes(n) else { return nil }
        let trimmed = raw.prefix { $0 != 0 }
        return String(decoding: trimmed, as: UTF8.self)
    }

    func slice(at start: Int, length: Int) -> Data? {
        guard canRead(length, at: start) else { return nil }
        let base = data.startIndex + start
        return Data(data[base..<(base + length)])
    }
}

extension Data {
    func u32(at offset: Int, bigEndian: Bool = false) -> UInt32? {
        var r = ByteReader(self, offset: offset)
        return r.u32(bigEndian)
    }
}

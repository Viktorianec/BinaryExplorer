//
//  ZipArchive.swift
//  BinaryExplorer
//
//  Minimal, dependency-free ZIP reader used to unpack .ipa containers.
//  Supports stored + deflate entries and ZIP64 central directories, which is
//  everything the App Store packaging pipeline emits.
//

import Foundation
import Compression

struct ZipEntry {
    var path: String
    var compressedSize: UInt64
    var uncompressedSize: UInt64
    var localHeaderOffset: UInt64
    var method: UInt16
    var crc32: UInt32
    var modified: Date?
    var externalAttributes: UInt32

    var isDirectory: Bool { path.hasSuffix("/") }
    /// Unix permission bits live in the high 16 bits of the external attributes.
    var posixPermissions: UInt16 { UInt16((externalAttributes >> 16) & 0xFFFF) }
    var isExecutableFile: Bool { !isDirectory && (posixPermissions & 0o111) != 0 }
}

enum ZipError: LocalizedError {
    case notAnArchive
    case corruptCentralDirectory
    case unsupportedMethod(UInt16)
    case inflateFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAnArchive:
            return "This file is not a ZIP/IPA container — no central directory found."
        case .corruptCentralDirectory:
            return "The archive's central directory is damaged."
        case .unsupportedMethod(let m):
            return "Unsupported ZIP compression method \(m)."
        case .inflateFailed(let name):
            return "Failed to decompress “\(name)”."
        }
    }
}

struct ZipArchive {
    let url: URL
    let entries: [ZipEntry]
    private let data: Data

    init(url: URL) throws {
        self.url = url
        // Memory-map: IPAs run to hundreds of megabytes and we only touch slices.
        self.data = try Data(contentsOf: url, options: .mappedIfSafe)
        self.entries = try Self.readCentralDirectory(data)
    }

    var totalCompressedSize: UInt64 { entries.reduce(0) { $0 + $1.compressedSize } }
    var totalUncompressedSize: UInt64 { entries.reduce(0) { $0 + $1.uncompressedSize } }

    // MARK: - Central directory

    private static func readCentralDirectory(_ data: Data) throws -> [ZipEntry] {
        guard let eocd = findEOCD(data) else { throw ZipError.notAnArchive }

        var entryCount = Int(eocd.entryCount)
        var directoryOffset = Int(eocd.directoryOffset)

        // ZIP64 end-of-central-directory locator sits immediately before the EOCD.
        if eocd.entryCount == 0xFFFF || eocd.directoryOffset == 0xFFFF_FFFF {
            let locatorOffset = eocd.position - 20
            if locatorOffset >= 0, data.u32(at: locatorOffset) == 0x0706_4B50 {
                var r = ByteReader(data, offset: locatorOffset + 8)
                if let z64 = r.u64(), Int(z64) < data.count,
                   data.u32(at: Int(z64)) == 0x0605_4B50 {
                    var zr = ByteReader(data, offset: Int(z64) + 32)
                    if let total = zr.u64(), let off = zr.u64() {
                        entryCount = Int(total)
                        directoryOffset = Int(off)
                    }
                }
            }
        }

        guard directoryOffset >= 0, directoryOffset < data.count else {
            throw ZipError.corruptCentralDirectory
        }

        var reader = ByteReader(data, offset: directoryOffset)
        var result: [ZipEntry] = []
        result.reserveCapacity(entryCount)

        while result.count < entryCount || entryCount == 0 {
            guard let signature = reader.u32(), signature == 0x0201_4B50 else { break }
            reader.skip(4)                                  // version made by / needed
            let flags = reader.u16() ?? 0
            let method = reader.u16() ?? 0
            let modTime = reader.u16() ?? 0
            let modDate = reader.u16() ?? 0
            let crc = reader.u32() ?? 0
            var compressed = UInt64(reader.u32() ?? 0)
            var uncompressed = UInt64(reader.u32() ?? 0)
            let nameLength = Int(reader.u16() ?? 0)
            let extraLength = Int(reader.u16() ?? 0)
            let commentLength = Int(reader.u16() ?? 0)
            reader.skip(4)                                  // disk no. + internal attrs
            let externalAttributes = reader.u32() ?? 0
            var localOffset = UInt64(reader.u32() ?? 0)

            guard let nameData = reader.bytes(nameLength) else { throw ZipError.corruptCentralDirectory }
            // Bit 11 marks UTF-8 names; older writers use CP437, which overlaps ASCII.
            let name = (flags & 0x800) != 0
                ? String(decoding: nameData, as: UTF8.self)
                : (String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self))

            if let extra = reader.bytes(extraLength) {
                applyZip64Extra(extra,
                                uncompressed: &uncompressed,
                                compressed: &compressed,
                                localOffset: &localOffset)
            }
            reader.skip(commentLength)

            result.append(ZipEntry(path: name,
                                   compressedSize: compressed,
                                   uncompressedSize: uncompressed,
                                   localHeaderOffset: localOffset,
                                   method: method,
                                   crc32: crc,
                                   modified: dosDate(date: modDate, time: modTime),
                                   externalAttributes: externalAttributes))
            if entryCount == 0 && result.count > 500_000 { break }
        }

        guard !result.isEmpty else { throw ZipError.corruptCentralDirectory }
        return result
    }

    /// Patches the 0xFFFFFFFF sentinels from the ZIP64 extended-information field.
    private static func applyZip64Extra(_ extra: Data,
                                        uncompressed: inout UInt64,
                                        compressed: inout UInt64,
                                        localOffset: inout UInt64) {
        var r = ByteReader(extra)
        while r.remaining >= 4 {
            guard let headerID = r.u16(), let size = r.u16() else { return }
            let end = r.offsetAfter(size)
            if headerID == 0x0001 {
                if uncompressed == 0xFFFF_FFFF, let v = r.u64() { uncompressed = v }
                if compressed == 0xFFFF_FFFF, let v = r.u64() { compressed = v }
                if localOffset == 0xFFFF_FFFF, let v = r.u64() { localOffset = v }
            }
            r.seek(to: end)
        }
    }

    private struct EOCD {
        var position: Int
        var entryCount: UInt16
        var directoryOffset: UInt32
    }

    private static func findEOCD(_ data: Data) -> EOCD? {
        let maxComment = 65_535 + 22
        let searchStart = max(0, data.count - maxComment)
        guard data.count >= 22 else { return nil }
        var i = data.count - 22
        while i >= searchStart {
            if data.u32(at: i) == 0x0605_4B50 {
                var r = ByteReader(data, offset: i + 10)
                let count = r.u16() ?? 0
                r.skip(4)                                   // directory size
                let offset = r.u32() ?? 0
                return EOCD(position: i, entryCount: count, directoryOffset: offset)
            }
            i -= 1
        }
        return nil
    }

    private static func dosDate(date: UInt16, time: UInt16) -> Date? {
        guard date != 0 else { return nil }
        var components = DateComponents()
        components.year = Int((date >> 9) & 0x7F) + 1980
        components.month = Int((date >> 5) & 0x0F)
        components.day = Int(date & 0x1F)
        components.hour = Int((time >> 11) & 0x1F)
        components.minute = Int((time >> 5) & 0x3F)
        components.second = Int(time & 0x1F) * 2
        return Calendar(identifier: .gregorian).date(from: components)
    }

    // MARK: - Extraction

    /// Reads and decompresses a single entry.
    func contents(of entry: ZipEntry) throws -> Data {
        guard entry.uncompressedSize > 0 else { return Data() }
        let headerStart = Int(entry.localHeaderOffset)
        guard data.u32(at: headerStart) == 0x0403_4B50 else { throw ZipError.corruptCentralDirectory }

        var r = ByteReader(data, offset: headerStart + 26)
        let nameLength = Int(r.u16() ?? 0)
        let extraLength = Int(r.u16() ?? 0)
        let payloadStart = headerStart + 30 + nameLength + extraLength
        guard let payload = r.slice(at: payloadStart, length: Int(entry.compressedSize)) else {
            throw ZipError.corruptCentralDirectory
        }

        switch entry.method {
        case 0:
            return payload
        case 8:
            guard let inflated = Self.inflate(payload, expectedSize: Int(entry.uncompressedSize)) else {
                throw ZipError.inflateFailed(entry.path)
            }
            return inflated
        default:
            throw ZipError.unsupportedMethod(entry.method)
        }
    }

    /// Raw-deflate decompression through the Compression framework.
    private static func inflate(_ input: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written: Int? = output.withUnsafeMutableBytes { outRaw -> Int? in
            guard let dst = outRaw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            return input.withUnsafeBytes { inRaw -> Int? in
                guard let src = inRaw.bindMemory(to: UInt8.self).baseAddress else { return nil }
                let n = compression_decode_buffer(dst, expectedSize, src, input.count, nil, COMPRESSION_ZLIB)
                return n > 0 ? n : nil
            }
        }
        guard let n = written else { return nil }
        return n == expectedSize ? output : output.prefix(n)
    }

    /// Unpacks the whole archive into `directory`, rejecting path-traversal entries.
    @discardableResult
    func extractAll(to directory: URL, progress: ((Double) -> Void)? = nil) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let total = max(1, entries.count)

        for (index, entry) in entries.enumerated() {
            defer { progress?(Double(index + 1) / Double(total)) }
            guard let destination = Self.safeDestination(for: entry.path, in: directory) else { continue }

            if entry.isDirectory {
                try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }
            try? fm.createDirectory(at: destination.deletingLastPathComponent(),
                                    withIntermediateDirectories: true)
            let payload = try contents(of: entry)
            try payload.write(to: destination, options: .atomic)
            if entry.isExecutableFile {
                try? fm.setAttributes([.posixPermissions: NSNumber(value: 0o755)],
                                      ofItemAtPath: destination.path)
            }
        }
        return directory
    }

    /// Guards against `../` escapes and absolute paths inside the archive.
    private static func safeDestination(for path: String, in root: URL) -> URL? {
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return nil }
        guard !components.contains("..") else { return nil }
        var url = root
        for component in components where !component.isEmpty {
            url.appendPathComponent(component)
        }
        return url.path.hasPrefix(root.path) ? url : nil
    }
}

private extension ByteReader {
    func offsetAfter(_ size: UInt16) -> Int { offset + Int(size) }
}

//
//  MachO.swift
//  BinaryExplorer
//
//  A read-only Mach-O parser: fat headers, slices, load commands, segments,
//  sections, linked libraries and the embedded code-signature blob.
//

import Foundation

// MARK: - Model

struct MachOSection: Identifiable, Hashable {
    var id: String { "\(segment).\(name).\(offset)" }
    var name: String
    var segment: String
    var address: UInt64
    var size: UInt64
    var offset: UInt64
    var flags: UInt32

    /// Zero-fill sections (__bss, __common) occupy VM but no file bytes.
    var isZeroFill: Bool { (flags & 0xFF) == 0x1 || (flags & 0xFF) == 0xC }
}

struct MachOSegment: Identifiable, Hashable {
    var id: String { "\(name)-\(fileOffset)" }
    var name: String
    var vmAddress: UInt64
    var vmSize: UInt64
    var fileOffset: UInt64
    var fileSize: UInt64
    var maxProtection: Int32
    var initProtection: Int32
    var sections: [MachOSection]

    var protectionDescription: String {
        func decode(_ p: Int32) -> String {
            var s = ""
            s += (p & 1) != 0 ? "r" : "-"
            s += (p & 2) != 0 ? "w" : "-"
            s += (p & 4) != 0 ? "x" : "-"
            return s
        }
        return "\(decode(initProtection))/\(decode(maxProtection))"
    }
}

struct LinkedLibrary: Identifiable, Hashable {
    var id: String { path + kind.rawValue }
    enum Kind: String {
        case required = "Required"
        case weak = "Weak"
        case reexport = "Re-export"
        case upward = "Upward"
        case lazy = "Lazy"
    }

    var path: String
    var kind: Kind
    var currentVersion: String
    var compatibilityVersion: String

    var name: String {
        (path as NSString).lastPathComponent
    }

    /// Anything not shipped by the OS is bundled with the app itself.
    var isSystem: Bool {
        path.hasPrefix("/System/") || path.hasPrefix("/usr/lib/")
    }

    var isEmbedded: Bool {
        path.hasPrefix("@rpath") || path.hasPrefix("@executable_path") || path.hasPrefix("@loader_path")
    }

    var origin: String {
        if path.hasPrefix("/System/Library/Frameworks") { return "System framework" }
        if path.hasPrefix("/System/Library/PrivateFrameworks") { return "Private framework" }
        if path.hasPrefix("/usr/lib") { return "System library" }
        if isEmbedded { return "Embedded" }
        return "Other"
    }
}

struct EncryptionInfo: Hashable {
    var offset: UInt64
    var size: UInt64
    var cryptID: UInt32
    var isEncrypted: Bool { cryptID != 0 }
}

struct LoadCommandTally: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var count: Int
}

struct MachOSlice: Identifiable, Hashable {
    var id: String { "\(architecture)-\(fileOffset)" }

    var architecture: String
    var cpuType: Int32
    var cpuSubtype: Int32
    var fileType: String
    var flags: [String]
    var fileOffset: UInt64
    var size: UInt64

    var uuid: UUID?
    var platform: String?
    var minimumOS: String?
    var sdk: String?
    var sourceVersion: String?
    var dylinker: String?
    var installName: String?

    var segments: [MachOSegment]
    var libraries: [LinkedLibrary]
    var rpaths: [String]
    var loadCommands: [LoadCommandTally]
    var symbolCount: Int
    var indirectSymbolCount: Int
    var encryption: EncryptionInfo?
    var codeSignature: CodeSignature?
    var hasChainedFixups: Bool
    var hasExportsTrie: Bool
    var entryPoint: UInt64?
    var isPositionIndependent: Bool

    var linkedSwift: Bool {
        segments.contains { $0.sections.contains { $0.name.hasPrefix("__swift5") } }
            || libraries.contains { $0.path.contains("libswift") }
    }

    var hasObjC: Bool {
        segments.contains { $0.sections.contains { $0.name.hasPrefix("__objc_") } }
    }

    var textSize: UInt64 { segments.first { $0.name == "__TEXT" }?.fileSize ?? 0 }
    var dataSize: UInt64 { segments.filter { $0.name.hasPrefix("__DATA") }.reduce(0) { $0 + $1.fileSize } }
    var linkEditSize: UInt64 { segments.first { $0.name == "__LINKEDIT" }?.fileSize ?? 0 }

    /// Every section across every segment, largest first — drives the treemap.
    var allSections: [MachOSection] {
        segments.flatMap(\.sections).sorted { $0.size > $1.size }
    }
}

struct MachOFile {
    var isFat: Bool
    var slices: [MachOSlice]
    var fileSize: UInt64

    var primarySlice: MachOSlice? {
        slices.first { $0.architecture.hasPrefix("arm64") } ?? slices.first
    }
}

// MARK: - Parser

enum MachOParser {

    private enum Magic {
        static let fat32: UInt32 = 0xCAFE_BABE
        static let fat64: UInt32 = 0xCAFE_BABF
        static let macho64: UInt32 = 0xFEED_FACF
        static let macho32: UInt32 = 0xFEED_FACE
        static let macho64Swapped: UInt32 = 0xCFFA_EDFE
        static let macho32Swapped: UInt32 = 0xCEFA_EDFE
    }

    static func isMachO(_ data: Data) -> Bool {
        guard let magic = data.u32(at: 0) else { return false }
        return [Magic.fat32, Magic.fat64, Magic.macho64, Magic.macho32,
                Magic.macho64Swapped, Magic.macho32Swapped].contains(magic)
            || data.u32(at: 0, bigEndian: true) == Magic.fat32
    }

    static func parse(url: URL) -> MachOFile? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return parse(data: data)
    }

    static func parse(data: Data) -> MachOFile? {
        guard let magic = data.u32(at: 0) else { return nil }

        // Fat headers are always big-endian.
        if magic == Magic.fat32.byteSwapped || magic == Magic.fat64.byteSwapped
            || magic == Magic.fat32 || magic == Magic.fat64 {
            let beMagic = data.u32(at: 0, bigEndian: true) ?? 0
            if beMagic == Magic.fat32 || beMagic == Magic.fat64 {
                return parseFat(data, is64: beMagic == Magic.fat64)
            }
        }

        guard let slice = parseSlice(data, at: 0, size: UInt64(data.count)) else { return nil }
        return MachOFile(isFat: false, slices: [slice], fileSize: UInt64(data.count))
    }

    private static func parseFat(_ data: Data, is64: Bool) -> MachOFile? {
        var r = ByteReader(data, offset: 4)
        guard let archCount = r.u32(true), archCount < 64 else { return nil }
        var slices: [MachOSlice] = []
        for _ in 0..<archCount {
            guard r.u32(true) != nil, r.u32(true) != nil else { break }   // cputype/subtype
            let offset: UInt64
            let size: UInt64
            if is64 {
                guard let o = r.u64(true), let s = r.u64(true) else { break }
                offset = o; size = s
                _ = r.u32(true); _ = r.u32(true)                          // align + reserved
            } else {
                guard let o = r.u32(true), let s = r.u32(true) else { break }
                offset = UInt64(o); size = UInt64(s)
                _ = r.u32(true)                                           // align
            }
            if let slice = parseSlice(data, at: Int(offset), size: size) {
                slices.append(slice)
            }
        }
        guard !slices.isEmpty else { return nil }
        return MachOFile(isFat: true, slices: slices, fileSize: UInt64(data.count))
    }

    // MARK: Slice

    private static func parseSlice(_ data: Data, at start: Int, size: UInt64) -> MachOSlice? {
        guard let magic = data.u32(at: start) else { return nil }
        let is64: Bool
        switch magic {
        case Magic.macho64, Magic.macho64Swapped: is64 = true
        case Magic.macho32, Magic.macho32Swapped: is64 = false
        default: return nil
        }

        var r = ByteReader(data, offset: start + 4)
        guard let cpuTypeRaw = r.u32(), let cpuSubRaw = r.u32(),
              let fileTypeRaw = r.u32(), let ncmds = r.u32(),
              r.u32() != nil, let flags = r.u32() else { return nil }
        if is64 { r.skip(4) }                                             // reserved

        let cpuType = Int32(bitPattern: cpuTypeRaw)
        let cpuSubtype = Int32(bitPattern: cpuSubRaw)

        var slice = MachOSlice(architecture: architectureName(cpuType, cpuSubtype),
                               cpuType: cpuType,
                               cpuSubtype: cpuSubtype,
                               fileType: fileTypeName(fileTypeRaw),
                               flags: headerFlags(flags),
                               fileOffset: UInt64(start),
                               size: size,
                               segments: [],
                               libraries: [],
                               rpaths: [],
                               loadCommands: [],
                               symbolCount: 0,
                               indirectSymbolCount: 0,
                               hasChainedFixups: false,
                               hasExportsTrie: false,
                               isPositionIndependent: (flags & 0x200000) != 0)

        var commandTally: [String: Int] = [:]
        var order: [String] = []

        for _ in 0..<min(ncmds, 4096) {
            let commandStart = r.offset
            guard let cmd = r.u32(), let cmdSize = r.u32(), cmdSize >= 8 else { break }
            let name = loadCommandName(cmd)
            if commandTally[name] == nil { order.append(name) }
            commandTally[name, default: 0] += 1

            switch cmd {
            case 0x19, 0x01:                                              // LC_SEGMENT_64 / LC_SEGMENT
                if let segment = parseSegment(&r, is64: cmd == 0x19) {
                    slice.segments.append(segment)
                }
            case 0x0C, 0x8000_0018, 0x8000_001F, 0x8000_0020, 0x20:        // dylib variants
                if let lib = parseDylib(&r, commandStart: commandStart, cmdSize: Int(cmdSize), cmd: cmd) {
                    slice.libraries.append(lib)
                }
            case 0x0D:                                                    // LC_ID_DYLIB
                if let lib = parseDylib(&r, commandStart: commandStart, cmdSize: Int(cmdSize), cmd: cmd) {
                    slice.installName = lib.path
                }
            case 0x8000_001C:                                             // LC_RPATH
                if let offset = r.u32(),
                   let str = cString(data, at: commandStart + Int(offset), limit: commandStart + Int(cmdSize)) {
                    slice.rpaths.append(str)
                }
            case 0x0E:                                                    // LC_LOAD_DYLINKER
                if let offset = r.u32() {
                    slice.dylinker = cString(data, at: commandStart + Int(offset), limit: commandStart + Int(cmdSize))
                }
            case 0x1B:                                                    // LC_UUID
                if let raw = r.bytes(16), raw.count == 16 {
                    slice.uuid = raw.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
                }
            case 0x32:                                                    // LC_BUILD_VERSION
                if let platform = r.u32(), let minos = r.u32(), let sdk = r.u32() {
                    slice.platform = platformName(platform)
                    slice.minimumOS = versionString(minos)
                    slice.sdk = versionString(sdk)
                }
            case 0x24, 0x25, 0x2F, 0x30:                                  // LC_VERSION_MIN_*
                if let minos = r.u32(), let sdk = r.u32() {
                    slice.minimumOS = versionString(minos)
                    slice.sdk = versionString(sdk)
                    if slice.platform == nil { slice.platform = legacyPlatformName(cmd) }
                }
            case 0x2A:                                                    // LC_SOURCE_VERSION
                if let v = r.u64() { slice.sourceVersion = sourceVersionString(v) }
            case 0x21, 0x2C:                                              // LC_ENCRYPTION_INFO(_64)
                if let off = r.u32(), let sz = r.u32(), let id = r.u32() {
                    slice.encryption = EncryptionInfo(offset: UInt64(off), size: UInt64(sz), cryptID: id)
                }
            case 0x1D:                                                    // LC_CODE_SIGNATURE
                if let off = r.u32(), let sz = r.u32() {
                    slice.codeSignature = CodeSignatureParser.parse(data,
                                                                    offset: start + Int(off),
                                                                    size: Int(sz))
                }
            case 0x02:                                                    // LC_SYMTAB
                _ = r.u32()
                if let nsyms = r.u32() { slice.symbolCount = Int(nsyms) }
            case 0x0B:                                                    // LC_DYSYMTAB
                r.skip(64)
                if let nindirect = r.u32() { slice.indirectSymbolCount = Int(nindirect) }
            case 0x8000_0028:                                             // LC_MAIN
                if let entry = r.u64() { slice.entryPoint = entry }
            case 0x8000_0034: slice.hasChainedFixups = true               // LC_DYLD_CHAINED_FIXUPS
            case 0x8000_0033: slice.hasExportsTrie = true                 // LC_DYLD_EXPORTS_TRIE
            default: break
            }

            r.seek(to: commandStart + Int(cmdSize))
            guard r.offset > commandStart, r.offset <= data.count else { break }
        }

        slice.loadCommands = order.map { LoadCommandTally(name: $0, count: commandTally[$0] ?? 0) }
        return slice
    }

    private static func parseSegment(_ r: inout ByteReader, is64: Bool) -> MachOSegment? {
        guard let name = r.fixedString(16) else { return nil }
        let vmAddr: UInt64, vmSize: UInt64, fileOff: UInt64, fileSize: UInt64
        if is64 {
            guard let a = r.u64(), let b = r.u64(), let c = r.u64(), let d = r.u64() else { return nil }
            vmAddr = a; vmSize = b; fileOff = c; fileSize = d
        } else {
            guard let a = r.u32(), let b = r.u32(), let c = r.u32(), let d = r.u32() else { return nil }
            vmAddr = UInt64(a); vmSize = UInt64(b); fileOff = UInt64(c); fileSize = UInt64(d)
        }
        guard let maxProt = r.u32(), let initProt = r.u32(), let nsects = r.u32(), r.u32() != nil else {
            return nil
        }

        var sections: [MachOSection] = []
        for _ in 0..<min(nsects, 512) {
            guard let sectName = r.fixedString(16), let segName = r.fixedString(16) else { break }
            let addr: UInt64, size: UInt64, offset: UInt32
            if is64 {
                guard let a = r.u64(), let s = r.u64(), let o = r.u32() else { break }
                addr = a; size = s; offset = o
            } else {
                guard let a = r.u32(), let s = r.u32(), let o = r.u32() else { break }
                addr = UInt64(a); size = UInt64(s); offset = o
            }
            r.skip(12)                                                    // align, reloff, nreloc
            let flags = r.u32() ?? 0
            r.skip(is64 ? 12 : 8)                                         // reserved fields
            sections.append(MachOSection(name: sectName,
                                         segment: segName,
                                         address: addr,
                                         size: size,
                                         offset: UInt64(offset),
                                         flags: flags))
        }

        return MachOSegment(name: name,
                            vmAddress: vmAddr,
                            vmSize: vmSize,
                            fileOffset: fileOff,
                            fileSize: fileSize,
                            maxProtection: Int32(bitPattern: maxProt),
                            initProtection: Int32(bitPattern: initProt),
                            sections: sections)
    }

    private static func parseDylib(_ r: inout ByteReader,
                                   commandStart: Int,
                                   cmdSize: Int,
                                   cmd: UInt32) -> LinkedLibrary? {
        guard let nameOffset = r.u32(), r.u32() != nil,
              let currentVersion = r.u32(), let compatVersion = r.u32() else { return nil }
        guard let path = cString(r.data, at: commandStart + Int(nameOffset), limit: commandStart + cmdSize) else {
            return nil
        }
        let kind: LinkedLibrary.Kind
        switch cmd {
        case 0x8000_0018: kind = .weak
        case 0x8000_001F: kind = .reexport
        case 0x8000_0020: kind = .upward
        case 0x20: kind = .lazy
        default: kind = .required
        }
        return LinkedLibrary(path: path,
                             kind: kind,
                             currentVersion: versionString(currentVersion),
                             compatibilityVersion: versionString(compatVersion))
    }

    private static func cString(_ data: Data, at offset: Int, limit: Int) -> String? {
        guard offset >= 0, offset < data.count else { return nil }
        let end = min(limit, data.count)
        guard offset < end else { return nil }
        var bytes: [UInt8] = []
        var i = data.startIndex + offset
        let endIndex = data.startIndex + end
        while i < endIndex, data[i] != 0 {
            bytes.append(data[i])
            i += 1
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: Naming tables

    static func architectureName(_ cpuType: Int32, _ subtype: Int32) -> String {
        let sub = subtype & 0x00FF_FFFF
        switch cpuType {
        case 0x0100_000C:                                                 // CPU_TYPE_ARM64
            switch sub {
            case 0: return "arm64"
            case 1: return "arm64e"
            case 2: return "arm64v8"
            default: return "arm64"
            }
        case 0x0200_000C: return "arm64_32"
        case 0x0000_000C:                                                 // CPU_TYPE_ARM
            switch sub {
            case 9: return "armv7"
            case 11: return "armv7s"
            case 12: return "armv7k"
            default: return "arm"
            }
        case 0x0100_0007: return "x86_64"
        case 0x0000_0007: return "i386"
        default: return "cpu:\(cpuType)"
        }
    }

    static func fileTypeName(_ value: UInt32) -> String {
        switch value {
        case 1: return "Object"
        case 2: return "Executable"
        case 4: return "Core"
        case 5: return "Preload"
        case 6: return "Dynamic library"
        case 7: return "Dynamic linker"
        case 8: return "Bundle"
        case 9: return "Dylib stub"
        case 10: return "Debug symbols"
        case 11: return "Kext bundle"
        case 12: return "Fileset"
        default: return "Type \(value)"
        }
    }

    static func headerFlags(_ flags: UInt32) -> [String] {
        let table: [(UInt32, String)] = [
            (0x1, "NOUNDEFS"), (0x2, "INCRLINK"), (0x4, "DYLDLINK"), (0x8, "BINDATLOAD"),
            (0x10, "PREBOUND"), (0x20, "SPLIT_SEGS"), (0x80, "TWOLEVEL"),
            (0x400, "WEAK_DEFINES"), (0x800, "BINDS_TO_WEAK"), (0x1000, "ALLOW_STACK_EXECUTION"),
            (0x2000, "ROOT_SAFE"), (0x8000, "NO_REEXPORTED_DYLIBS"), (0x20_0000, "PIE"),
            (0x80_0000, "HAS_TLV_DESCRIPTORS"), (0x100_0000, "NO_HEAP_EXECUTION"),
            (0x800_0000, "APP_EXTENSION_SAFE"), (0x8000_0000, "DYLIB_IN_CACHE")
        ]
        return table.filter { flags & $0.0 != 0 }.map(\.1)
    }

    static func loadCommandName(_ cmd: UInt32) -> String {
        let table: [UInt32: String] = [
            0x01: "LC_SEGMENT", 0x02: "LC_SYMTAB", 0x04: "LC_THREAD", 0x05: "LC_UNIXTHREAD",
            0x0B: "LC_DYSYMTAB", 0x0C: "LC_LOAD_DYLIB", 0x0D: "LC_ID_DYLIB",
            0x0E: "LC_LOAD_DYLINKER", 0x0F: "LC_ID_DYLINKER", 0x11: "LC_PREBOUND_DYLIB",
            0x16: "LC_TWOLEVEL_HINTS", 0x19: "LC_SEGMENT_64", 0x1A: "LC_ROUTINES_64",
            0x1B: "LC_UUID", 0x1D: "LC_CODE_SIGNATURE", 0x1E: "LC_SEGMENT_SPLIT_INFO",
            0x20: "LC_LAZY_LOAD_DYLIB", 0x21: "LC_ENCRYPTION_INFO", 0x22: "LC_DYLD_INFO",
            0x24: "LC_VERSION_MIN_MACOSX", 0x25: "LC_VERSION_MIN_IPHONEOS",
            0x26: "LC_FUNCTION_STARTS", 0x27: "LC_DYLD_ENVIRONMENT", 0x29: "LC_DATA_IN_CODE",
            0x2A: "LC_SOURCE_VERSION", 0x2B: "LC_DYLIB_CODE_SIGN_DRS",
            0x2C: "LC_ENCRYPTION_INFO_64", 0x2D: "LC_LINKER_OPTION",
            0x2E: "LC_LINKER_OPTIMIZATION_HINT", 0x2F: "LC_VERSION_MIN_TVOS",
            0x30: "LC_VERSION_MIN_WATCHOS", 0x31: "LC_NOTE", 0x32: "LC_BUILD_VERSION",
            0x33: "LC_DYLD_EXPORTS_TRIE", 0x34: "LC_DYLD_CHAINED_FIXUPS",
            0x35: "LC_FILESET_ENTRY", 0x36: "LC_ATOM_INFO",
            0x8000_0012: "LC_PREBOUND_DYLIB", 0x8000_0016: "LC_SUB_FRAMEWORK",
            0x8000_0018: "LC_LOAD_WEAK_DYLIB", 0x8000_001C: "LC_RPATH",
            0x8000_001F: "LC_REEXPORT_DYLIB", 0x8000_0020: "LC_LAZY_LOAD_DYLIB",
            0x8000_0022: "LC_DYLD_INFO_ONLY", 0x8000_0028: "LC_MAIN",
            0x8000_0033: "LC_DYLD_EXPORTS_TRIE", 0x8000_0034: "LC_DYLD_CHAINED_FIXUPS"
        ]
        return table[cmd] ?? String(format: "LC_0x%X", cmd)
    }

    static func platformName(_ value: UInt32) -> String {
        switch value {
        case 1: return "macOS"
        case 2: return "iOS"
        case 3: return "tvOS"
        case 4: return "watchOS"
        case 5: return "bridgeOS"
        case 6: return "Mac Catalyst"
        case 7: return "iOS Simulator"
        case 8: return "tvOS Simulator"
        case 9: return "watchOS Simulator"
        case 10: return "DriverKit"
        case 11: return "visionOS"
        case 12: return "visionOS Simulator"
        default: return "Platform \(value)"
        }
    }

    private static func legacyPlatformName(_ cmd: UInt32) -> String {
        switch cmd {
        case 0x24: return "macOS"
        case 0x25: return "iOS"
        case 0x2F: return "tvOS"
        case 0x30: return "watchOS"
        default: return "Unknown"
        }
    }

    /// X.Y.Z packed as xxxx.yy.zz in a 32-bit word.
    static func versionString(_ value: UInt32) -> String {
        let major = value >> 16
        let minor = (value >> 8) & 0xFF
        let patch = value & 0xFF
        return patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }

    static func sourceVersionString(_ value: UInt64) -> String {
        let a = value >> 40
        let b = (value >> 30) & 0x3FF
        let c = (value >> 20) & 0x3FF
        let d = (value >> 10) & 0x3FF
        let e = value & 0x3FF
        return "\(a).\(b).\(c).\(d).\(e)"
    }
}

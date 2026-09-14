//
//  AssetCatalog.swift
//  BinaryExplorer
//
//  A light structural probe of a compiled Assets.car. The file is a BOM store:
//  a block table plus named variables, several of which are B-trees whose path
//  counts tell us how many named assets and renditions the catalog holds.
//

import Foundation

struct AssetCatalogInfo {
    var fileSize: UInt64
    var coreUIVersion: UInt32?
    var storageVersion: UInt32?
    var schemaVersion: UInt32?
    var renditionCount: Int?
    var namedAssetCount: Int?
    var appearanceCount: Int?
    var colorCount: Int?
    var externalRenditionCount: Int?
    var creator: String?
    var toolchain: String?
    var storageTimestamp: Date?
    var uuid: UUID?
    var variables: [String]

    var isLegible: Bool { coreUIVersion != nil || !variables.isEmpty }
}

enum AssetCatalogProbe {

    private struct Block {
        var address: Int
        var length: Int
    }

    static func probe(url: URL) -> AssetCatalogInfo? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let size = UInt64(data.count)
        guard data.count > 32, data.prefix(8) == Data("BOMStore".utf8) else {
            return AssetCatalogInfo(fileSize: size, variables: [])
        }

        var header = ByteReader(data, offset: 8)
        guard header.u32(true) != nil,                       // version
              header.u32(true) != nil,                       // block count
              let indexOffset = header.u32(true),
              header.u32(true) != nil,                       // index length
              let varsOffset = header.u32(true) else {
            return AssetCatalogInfo(fileSize: size, variables: [])
        }

        let blocks = readBlockTable(data, at: Int(indexOffset))
        let variables = readVariables(data, at: Int(varsOffset))

        var info = AssetCatalogInfo(fileSize: size, variables: variables.map(\.name).sorted())

        func block(_ name: String) -> Block? {
            guard let index = variables.first(where: { $0.name == name })?.index,
                  index > 0, index < blocks.count else { return nil }
            return blocks[index]
        }

        if let header = block("CARHEADER") { readCARHeader(data, block: header, into: &info) }
        info.renditionCount = block("RENDITIONS").flatMap { treePathCount(data, block: $0, blocks: blocks) }
            ?? info.renditionCount
        info.namedAssetCount = block("FACETKEYS").flatMap { treePathCount(data, block: $0, blocks: blocks) }
        info.appearanceCount = block("APPEARANCEKEYS").flatMap { treePathCount(data, block: $0, blocks: blocks) }
        info.colorCount = block("COLORS").flatMap { treePathCount(data, block: $0, blocks: blocks) }
        info.externalRenditionCount = block("EXTERNAL_KEYS").flatMap { treePathCount(data, block: $0, blocks: blocks) }

        return info
    }

    private static func readBlockTable(_ data: Data, at offset: Int) -> [Block] {
        var r = ByteReader(data, offset: offset)
        guard let count = r.u32(true), count < 2_000_000 else { return [] }
        var blocks: [Block] = []
        blocks.reserveCapacity(Int(count) + 1)
        for _ in 0...count {
            guard let address = r.u32(true), let length = r.u32(true) else { break }
            blocks.append(Block(address: Int(address), length: Int(length)))
        }
        return blocks
    }

    private static func readVariables(_ data: Data, at offset: Int) -> [(name: String, index: Int)] {
        var r = ByteReader(data, offset: offset)
        guard let count = r.u32(true), count < 4096 else { return [] }
        var result: [(String, Int)] = []
        for _ in 0..<count {
            guard let index = r.u32(true), let length = r.u8(),
                  let raw = r.bytes(Int(length)) else { break }
            result.append((String(decoding: raw, as: UTF8.self), Int(index)))
        }
        return result
    }

    private static func readCARHeader(_ data: Data, block: Block, into info: inout AssetCatalogInfo) {
        var r = ByteReader(data, offset: block.address)
        guard r.canRead(min(block.length, 428)), r.u32(true) != nil else { return }   // 'CTAR'
        info.coreUIVersion = r.u32()
        info.storageVersion = r.u32()
        if let timestamp = r.u32(), timestamp > 0 {
            info.storageTimestamp = Date(timeIntervalSince1970: TimeInterval(timestamp))
        }
        if let renditions = r.u32() { info.renditionCount = Int(renditions) }
        info.creator = r.fixedString(128)?.trimmed()
        info.toolchain = r.fixedString(256)?.trimmed()
        if let raw = r.bytes(16), raw.count == 16 {
            info.uuid = raw.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }
        }
        _ = r.u32()                                                                   // associated checksum
        info.schemaVersion = r.u32()
    }

    /// A BOM "tree" block stores the number of leaf paths in its header.
    private static func treePathCount(_ data: Data, block: Block, blocks: [Block]) -> Int? {
        var r = ByteReader(data, offset: block.address)
        guard let tag = r.bytes(4), tag == Data("tree".utf8) else { return nil }
        guard r.u32(true) != nil, r.u32(true) != nil, r.u32(true) != nil,             // version, child, blockSize
              let pathCount = r.u32(true) else { return nil }
        return Int(pathCount)
    }
}

private extension String {
    func trimmed() -> String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

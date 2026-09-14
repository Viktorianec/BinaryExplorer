//
//  Format.swift
//  BinaryExplorer
//
//  Shared formatting so every number in the app reads the same way.
//

import Foundation

enum Format {

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func bytes(_ value: UInt64) -> String {
        byteFormatter.string(fromByteCount: Int64(clamping: value))
    }

    static func bytes(_ value: Int) -> String {
        byteFormatter.string(fromByteCount: Int64(value))
    }

    static func count(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    static func date(_ value: Date?) -> String {
        guard let value else { return "—" }
        return dateFormatter.string(from: value)
    }

    static func day(_ value: Date?) -> String {
        guard let value else { return "—" }
        return dayFormatter.string(from: value)
    }

    static func hex(_ value: UInt64, width: Int = 8) -> String {
        String(format: "0x%0\(width)llX", value)
    }

    static func duration(_ value: TimeInterval) -> String {
        value < 1 ? String(format: "%.0f ms", value * 1000) : String(format: "%.2f s", value)
    }

    /// Splits a UUID-style hash into readable groups.
    static func fingerprint(_ value: String, groupSize: Int = 8) -> String {
        stride(from: 0, to: value.count, by: groupSize).map { offset -> String in
            let start = value.index(value.startIndex, offsetBy: offset)
            let end = value.index(start, offsetBy: min(groupSize, value.count - offset))
            return String(value[start..<end])
        }.joined(separator: " ")
    }

    /// Human label for a `public.app-category.*` identifier.
    static func appCategory(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let leaf = identifier.replacingOccurrences(of: "public.app-category.", with: "")
        return leaf.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

//
//  AnalysisModel.swift
//  BinaryExplorer
//
//  The value types the UI renders. Everything here is produced once by
//  IPAAnalyzer and then treated as immutable.
//

import Foundation
import AppKit

// MARK: - File tree

final class FileNode: Identifiable, Hashable {
    let id: String
    let name: String
    let relativePath: String
    let url: URL
    let isDirectory: Bool
    let kind: FileKind
    /// Bytes on disk for a file; the recursive sum for a directory.
    let size: UInt64
    let compressedSize: UInt64
    private(set) var children: [FileNode]
    weak var parent: FileNode?

    init(id: String,
         name: String,
         relativePath: String,
         url: URL,
         isDirectory: Bool,
         kind: FileKind,
         size: UInt64,
         compressedSize: UInt64,
         children: [FileNode]) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.url = url
        self.isDirectory = isDirectory
        self.kind = kind
        self.size = size
        self.compressedSize = compressedSize
        self.children = children
        for child in children { child.parent = self }
    }

    var fileCount: Int {
        isDirectory ? children.reduce(0) { $0 + $1.fileCount } : 1
    }

    var sortedChildren: [FileNode] {
        children.sorted { lhs, rhs in
            if lhs.size != rhs.size { return lhs.size > rhs.size }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func flattened() -> [FileNode] {
        isDirectory ? [self] + children.flatMap { $0.flattened() } : [self]
    }

    func allFiles() -> [FileNode] {
        isDirectory ? children.flatMap { $0.allFiles() } : [self]
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Bundles

struct PrivacyManifest: Identifiable, Hashable {
    var id: String { owner }
    var owner: String
    var tracking: Bool
    var trackingDomains: [String]
    var collectedDataTypes: [String]
    var accessedAPITypes: [String]
}

struct BundleInfo: Identifiable {
    enum Kind: String {
        case application = "Application"
        case appExtension = "App extension"
        case watchApp = "Watch app"
        case framework = "Framework"
        case resourceBundle = "Resource bundle"

        var symbol: String {
            switch self {
            case .application: return "app.badge.fill"
            case .appExtension: return "puzzlepiece.extension.fill"
            case .watchApp: return "applewatch"
            case .framework: return "shippingbox.fill"
            case .resourceBundle: return "archivebox.fill"
            }
        }

        var fileKind: FileKind {
            switch self {
            case .application: return .executable
            case .appExtension: return .appExtension
            case .watchApp: return .watchApp
            case .framework: return .framework
            case .resourceBundle: return .resourceBundle
            }
        }
    }

    var id: String { relativePath }
    var kind: Kind
    var name: String
    var relativePath: String
    var url: URL
    var size: UInt64

    var infoPlist: [String: Any]
    var executableURL: URL?
    var machO: MachOFile?
    var icon: NSImage?
    var provisioning: ProvisioningProfile?
    var assetCatalog: AssetCatalogInfo?
    var privacyManifest: PrivacyManifest?
    var localizations: [String]
    var children: [BundleInfo]

    // Convenience accessors over Info.plist.
    var displayName: String {
        (infoPlist["CFBundleDisplayName"] as? String)
            ?? (infoPlist["CFBundleName"] as? String)
            ?? name
    }
    var bundleIdentifier: String { infoPlist["CFBundleIdentifier"] as? String ?? "—" }
    var shortVersion: String { infoPlist["CFBundleShortVersionString"] as? String ?? "—" }
    var buildNumber: String { infoPlist["CFBundleVersion"] as? String ?? "—" }
    var minimumOS: String? {
        (infoPlist["MinimumOSVersion"] as? String) ?? (infoPlist["LSMinimumSystemVersion"] as? String)
    }
    var platforms: [String] { infoPlist["CFBundleSupportedPlatforms"] as? [String] ?? [] }
    var sdkName: String? { infoPlist["DTSDKName"] as? String }
    var xcodeBuild: String? { infoPlist["DTXcodeBuild"] as? String }
    var xcodeVersion: String? {
        guard let raw = infoPlist["DTXcode"] as? String, raw.count >= 3, let value = Int(raw) else { return nil }
        let major = value / 100
        let minor = (value % 100) / 10
        let patch = value % 10
        return patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }
    var buildMachineOS: String? { infoPlist["BuildMachineOSBuild"] as? String }
    var categoryIdentifier: String? { infoPlist["LSApplicationCategoryType"] as? String }
    var deviceFamilies: [String] {
        let raw = infoPlist["UIDeviceFamily"] as? [Int] ?? []
        return raw.map {
            switch $0 {
            case 1: return "iPhone"
            case 2: return "iPad"
            case 3: return "Apple TV"
            case 4: return "Apple Watch"
            case 6: return "Apple Vision"
            default: return "Family \($0)"
            }
        }
    }
    var extensionPointIdentifier: String? {
        (infoPlist["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String
    }
    var urlSchemes: [String] {
        (infoPlist["CFBundleURLTypes"] as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
    }
    var backgroundModes: [String] { infoPlist["UIBackgroundModes"] as? [String] ?? [] }
    var requiredCapabilities: [String] { infoPlist["UIRequiredDeviceCapabilities"] as? [String] ?? [] }
    var supportedOrientations: [String] {
        (infoPlist["UISupportedInterfaceOrientations"] as? [String] ?? [])
            .map { $0.replacingOccurrences(of: "UIInterfaceOrientation", with: "") }
    }
    var usageDescriptions: [(key: String, value: String)] {
        infoPlist.compactMap { key, value in
            guard key.hasSuffix("UsageDescription"), let text = value as? String else { return nil }
            return (key, text)
        }.sorted { $0.key < $1.key }
    }
    var appTransportSecurity: [String: Any]? { infoPlist["NSAppTransportSecurity"] as? [String: Any] }
    var encryptionDeclared: Bool? { infoPlist["ITSAppUsesNonExemptEncryption"] as? Bool }

    var entitlements: [String: Any]? {
        machO?.primarySlice?.codeSignature?.entitlements ?? provisioning?.entitlements
    }

    var allDescendants: [BundleInfo] {
        children + children.flatMap(\.allDescendants)
    }
}

// MARK: - Insights

struct Insight: Identifiable {
    enum Level: Int, Comparable {
        case critical = 0, warning = 1, notice = 2, positive = 3

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .critical: return "Critical"
            case .warning: return "Warning"
            case .notice: return "Notice"
            case .positive: return "Healthy"
            }
        }

        var symbol: String {
            switch self {
            case .critical: return "exclamationmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .notice: return "info.circle.fill"
            case .positive: return "checkmark.seal.fill"
            }
        }
    }

    let id = UUID()
    var level: Level
    var title: String
    var detail: String
    var category: String
}

// MARK: - Category rollup

struct CategoryTotal: Identifiable {
    var id: String { label ?? kind.rawValue }
    var kind: FileKind
    var size: UInt64
    var fileCount: Int
    /// Set when the row is a roll-up rather than a single kind.
    var label: String?

    var title: String { label ?? kind.title }
}

// MARK: - Analysis root

struct IPAAnalysis {
    var sourceURL: URL
    var archiveSize: UInt64
    var uncompressedSize: UInt64
    var entryCount: Int
    var extractionRoot: URL
    var payloadRoot: FileNode
    var app: BundleInfo
    var insights: [Insight]
    var categories: [CategoryTotal]
    var privacyManifests: [PrivacyManifest]
    var analyzedAt: Date
    var analysisDuration: TimeInterval

    var compressionRatio: Double {
        uncompressedSize > 0 ? Double(archiveSize) / Double(uncompressedSize) : 1
    }

    var allBundles: [BundleInfo] { [app] + app.allDescendants }

    var embeddedFrameworks: [BundleInfo] { allBundles.filter { $0.kind == .framework } }
    var appExtensions: [BundleInfo] { allBundles.filter { $0.kind == .appExtension } }
    var watchApps: [BundleInfo] { allBundles.filter { $0.kind == .watchApp } }
    var resourceBundles: [BundleInfo] { allBundles.filter { $0.kind == .resourceBundle } }

    /// Every localization folder found anywhere in the payload.
    var localizations: [String] {
        Array(Set(allBundles.flatMap(\.localizations))).sorted()
    }

    var largestFiles: [FileNode] {
        payloadRoot.allFiles().sorted { $0.size > $1.size }
    }
}

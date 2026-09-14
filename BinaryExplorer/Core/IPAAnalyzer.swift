//
//  IPAAnalyzer.swift
//  BinaryExplorer
//
//  Unpacks an .ipa into a scratch directory and walks it into the immutable
//  IPAAnalysis the UI renders.
//

import Foundation
import AppKit

enum AnalysisStage: String {
    case reading = "Reading archive"
    case extracting = "Unpacking payload"
    case scanning = "Indexing bundle"
    case parsingBinaries = "Parsing Mach-O binaries"
    case signing = "Verifying signature"
    case finishing = "Building report"
}

struct AnalysisProgress {
    var stage: AnalysisStage
    var fraction: Double
}

enum AnalysisError: LocalizedError {
    case noPayload
    case noApplication

    var errorDescription: String? {
        switch self {
        case .noPayload: return "The archive has no Payload/ directory — this is not an iOS .ipa."
        case .noApplication: return "No .app bundle was found inside Payload/."
        }
    }
}

struct IPAAnalyzer {

    /// Entry point. Runs off the main actor; reports coarse progress as it goes.
    static func analyze(url: URL, progress: @escaping (AnalysisProgress) -> Void) throws -> IPAAnalysis {
        let started = Date()
        progress(AnalysisProgress(stage: .reading, fraction: 0.02))

        let archive = try ZipArchive(url: url)
        let archiveSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0

        // Compressed sizes only exist in the archive, so remember them by path.
        var compressedByPath: [String: UInt64] = [:]
        for entry in archive.entries where !entry.isDirectory {
            compressedByPath[entry.path] = entry.compressedSize
        }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("BinaryExplorer", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        progress(AnalysisProgress(stage: .extracting, fraction: 0.05))
        try archive.extractAll(to: workspace) { value in
            progress(AnalysisProgress(stage: .extracting, fraction: 0.05 + value * 0.45))
        }

        let payloadURL = workspace.appendingPathComponent("Payload", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: payloadURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw AnalysisError.noPayload
        }

        progress(AnalysisProgress(stage: .scanning, fraction: 0.55))
        guard let payloadNode = buildTree(at: payloadURL,
                                          relativeTo: workspace,
                                          compressed: compressedByPath) else {
            throw AnalysisError.noPayload
        }

        let appURLs = (try? FileManager.default.contentsOfDirectory(at: payloadURL,
                                                                   includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "app" } ?? []
        guard let appURL = appURLs.first else { throw AnalysisError.noApplication }

        progress(AnalysisProgress(stage: .parsingBinaries, fraction: 0.65))
        let app = buildBundle(at: appURL, kind: .application, root: workspace, tree: payloadNode)

        progress(AnalysisProgress(stage: .signing, fraction: 0.88))
        let manifests = collectPrivacyManifests(root: payloadURL)
        let categories = rollUpCategories(payloadNode)

        progress(AnalysisProgress(stage: .finishing, fraction: 0.95))
        var analysis = IPAAnalysis(sourceURL: url,
                                   archiveSize: archiveSize,
                                   uncompressedSize: payloadNode.size,
                                   entryCount: archive.entries.count,
                                   extractionRoot: workspace,
                                   payloadRoot: payloadNode,
                                   app: app,
                                   insights: [],
                                   categories: categories,
                                   privacyManifests: manifests,
                                   analyzedAt: started,
                                   analysisDuration: Date().timeIntervalSince(started))
        analysis.insights = InsightEngine.evaluate(analysis)
        progress(AnalysisProgress(stage: .finishing, fraction: 1.0))
        return analysis
    }

    /// Bundle-relative path. Both sides are resolved first: the scratch
    /// directory lives under /var, which is a symlink to /private/var, and the
    /// enumerator hands back the resolved form.
    private static func relativePath(of url: URL, root: URL) -> String {
        let rootComponents = root.resolvingSymlinksInPath().standardized.pathComponents
        let urlComponents = url.resolvingSymlinksInPath().standardized.pathComponents
        guard urlComponents.count > rootComponents.count,
              Array(urlComponents.prefix(rootComponents.count)) == rootComponents else {
            return url.lastPathComponent
        }
        return urlComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    // MARK: - Tree

    private static func buildTree(at url: URL,
                                  relativeTo root: URL,
                                  compressed: [String: UInt64]) -> FileNode? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }

        let relativePath = relativePath(of: url, root: root)
        let kind = FileKind.classify(url: url, isDirectory: isDirectory.boolValue)

        if isDirectory.boolValue {
            let contents = (try? fm.contentsOfDirectory(at: url,
                                                        includingPropertiesForKeys: [.fileSizeKey],
                                                        options: [.skipsHiddenFiles])) ?? []
            let children = contents.compactMap { buildTree(at: $0, relativeTo: root, compressed: compressed) }
            let total = children.reduce(UInt64(0)) { $0 + $1.size }
            let totalCompressed = children.reduce(UInt64(0)) { $0 + $1.compressedSize }
            // A directory inside a .app is only a "watch app" if it really is one.
            let resolved: FileKind = (kind == .watchApp && !relativePath.contains("/Watch/"))
                ? .executable : kind
            return FileNode(id: relativePath,
                            name: url.lastPathComponent,
                            relativePath: relativePath,
                            url: url,
                            isDirectory: true,
                            kind: resolved,
                            size: total,
                            compressedSize: totalCompressed,
                            children: children)
        }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { UInt64($0) } ?? 0
        var resolvedKind = kind
        // An extension-less file that starts with a Mach-O magic is a binary.
        if resolvedKind == .other, url.pathExtension.isEmpty, size > 4,
           let head = try? FileHandle(forReadingFrom: url).read(upToCount: 4), MachOParser.isMachO(head) {
            resolvedKind = .executable
        }

        return FileNode(id: relativePath,
                        name: url.lastPathComponent,
                        relativePath: relativePath,
                        url: url,
                        isDirectory: false,
                        kind: resolvedKind,
                        size: size,
                        compressedSize: compressed[relativePath] ?? size,
                        children: [])
    }

    private static func node(for url: URL, in tree: FileNode, root: URL) -> FileNode? {
        let relative = relativePath(of: url, root: root)
        return tree.flattened().first { $0.relativePath == relative }
    }

    // MARK: - Bundles

    private static func buildBundle(at url: URL,
                                    kind: BundleInfo.Kind,
                                    root: URL,
                                    tree: FileNode) -> BundleInfo {
        let fm = FileManager.default
        let relativePath = relativePath(of: url, root: root)
        let infoPlistURL = url.appendingPathComponent("Info.plist")
        let infoPlist = (try? Data(contentsOf: infoPlistURL))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
            ?? [:]

        var executableURL: URL?
        if let name = infoPlist["CFBundleExecutable"] as? String {
            let candidate = url.appendingPathComponent(name)
            if fm.fileExists(atPath: candidate.path) { executableURL = candidate }
        }
        if executableURL == nil, kind == .framework {
            let candidate = url.appendingPathComponent(url.deletingPathExtension().lastPathComponent)
            if fm.fileExists(atPath: candidate.path) { executableURL = candidate }
        }

        let machO = executableURL.flatMap { MachOParser.parse(url: $0) }
        let provisioning = (try? Data(contentsOf: url.appendingPathComponent("embedded.mobileprovision")))
            .flatMap { ProvisioningProfile.parse(data: $0) }
        let assetCatalog = AssetCatalogProbe.probe(url: url.appendingPathComponent("Assets.car"))
        let icon = loadIcon(bundleURL: url, infoPlist: infoPlist)
        let privacy = readPrivacyManifest(at: url.appendingPathComponent("PrivacyInfo.xcprivacy"),
                                          owner: url.lastPathComponent)

        let contents = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        let localizations = contents.filter { $0.pathExtension == "lproj" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()

        var children: [BundleInfo] = []
        func scan(_ directory: String, as childKind: BundleInfo.Kind, extensions: Set<String>) {
            let folder = url.appendingPathComponent(directory, isDirectory: true)
            let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for item in items where extensions.contains(item.pathExtension) {
                children.append(buildBundle(at: item, kind: childKind, root: root, tree: tree))
            }
        }
        scan("Frameworks", as: .framework, extensions: ["framework", "dylib"])
        scan("PlugIns", as: .appExtension, extensions: ["appex"])
        scan("Extensions", as: .appExtension, extensions: ["appex"])
        scan("Watch", as: .watchApp, extensions: ["app"])

        for item in contents where item.pathExtension == "bundle" {
            children.append(buildBundle(at: item, kind: .resourceBundle, root: root, tree: tree))
        }

        let size = node(for: url, in: tree, root: root)?.size
            ?? directorySize(url)

        return BundleInfo(kind: kind,
                          name: url.deletingPathExtension().lastPathComponent,
                          relativePath: relativePath,
                          url: url,
                          size: size,
                          infoPlist: infoPlist,
                          executableURL: executableURL,
                          machO: machO,
                          icon: icon,
                          provisioning: provisioning,
                          assetCatalog: assetCatalog,
                          privacyManifest: privacy,
                          localizations: localizations,
                          children: children.sorted { $0.size > $1.size })
    }

    private static func directorySize(_ url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(at: url,
                                                              includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: UInt64 = 0
        for case let item as URL in enumerator {
            total += (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { UInt64($0) } ?? 0
        }
        return total
    }

    /// iOS keeps loose icon PNGs at the bundle root so the installer can read
    /// them without opening the asset catalog — that's what we display.
    private static func loadIcon(bundleURL: URL, infoPlist: [String: Any]) -> NSImage? {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(at: bundleURL, includingPropertiesForKeys: nil)) ?? []

        var declared: [String] = []
        for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            if let icons = infoPlist[key] as? [String: Any],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
               let files = primary["CFBundleIconFiles"] as? [String] {
                declared.append(contentsOf: files)
            }
        }
        if let files = infoPlist["CFBundleIconFiles"] as? [String] { declared.append(contentsOf: files) }

        let candidates = contents.filter { url in
            guard url.pathExtension.lowercased() == "png" else { return false }
            let name = url.deletingPathExtension().lastPathComponent
            if declared.contains(where: { name.hasPrefix($0) }) { return true }
            return name.hasPrefix("AppIcon") || name.hasPrefix("Icon")
        }

        // Prefer the highest-resolution rendition available.
        let best = candidates
            .compactMap { url -> (URL, Int)? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = props[kCGImagePropertyPixelWidth] as? Int else { return nil }
                return (url, width)
            }
            .max { $0.1 < $1.1 }?.0

        guard let best else { return nil }
        return NSImage(contentsOf: best)
    }

    private static func readPrivacyManifest(at url: URL, owner: String) -> PrivacyManifest? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any] else { return nil }

        let collected = (plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]] ?? [])
            .compactMap { $0["NSPrivacyCollectedDataType"] as? String }
            .map { $0.replacingOccurrences(of: "NSPrivacyCollectedDataType", with: "") }
        let apis = (plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? [])
            .compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
            .map { $0.replacingOccurrences(of: "NSPrivacyAccessedAPICategory", with: "") }

        return PrivacyManifest(owner: owner,
                               tracking: plist["NSPrivacyTracking"] as? Bool ?? false,
                               trackingDomains: plist["NSPrivacyTrackingDomains"] as? [String] ?? [],
                               collectedDataTypes: collected,
                               accessedAPITypes: apis)
    }

    private static func collectPrivacyManifests(root: URL) -> [PrivacyManifest] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var result: [PrivacyManifest] = []
        for case let url as URL in enumerator where url.lastPathComponent == "PrivacyInfo.xcprivacy" {
            let owner = url.deletingLastPathComponent().lastPathComponent
            if let manifest = readPrivacyManifest(at: url, owner: owner) {
                result.append(manifest)
            }
        }
        return result.sorted { $0.owner.localizedStandardCompare($1.owner) == .orderedAscending }
    }

    private static func rollUpCategories(_ root: FileNode) -> [CategoryTotal] {
        var sizes: [FileKind: (UInt64, Int)] = [:]
        for file in root.allFiles() {
            var entry = sizes[file.kind] ?? (0, 0)
            entry.0 += file.size
            entry.1 += 1
            sizes[file.kind] = entry
        }
        return sizes.map { CategoryTotal(kind: $0.key, size: $0.value.0, fileCount: $0.value.1, label: nil) }
            .sorted { $0.size > $1.size }
    }
}

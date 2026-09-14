//
//  AppState.swift
//  BinaryExplorer
//
//  Single observable store: the loaded analysis, navigation state, search and
//  the currently inspected resource.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

enum ExplorerSection: String, CaseIterable, Identifiable {
    case overview
    case spatial
    case structure
    case resources
    case binary
    case dependencies
    case signing
    case privacy
    case insights
    case metadata
    case anatomy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .spatial: return "Spatial"
        case .structure: return "Structure"
        case .resources: return "Resources"
        case .binary: return "Mach-O"
        case .dependencies: return "Dependencies"
        case .signing: return "Signing"
        case .privacy: return "Privacy & ATS"
        case .insights: return "Insights"
        case .metadata: return "Info.plist"
        case .anatomy: return "Anatomy"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .spatial: return "cube.transparent.fill"
        case .structure: return "list.bullet.indent"
        case .resources: return "photo.stack.fill"
        case .binary: return "cpu.fill"
        case .dependencies: return "point.3.filled.connected.trianglepath.dotted"
        case .signing: return "checkmark.seal.fill"
        case .privacy: return "hand.raised.fill"
        case .insights: return "sparkles"
        case .metadata: return "doc.text.magnifyingglass"
        case .anatomy: return "book.closed.fill"
        }
    }

    var tint: Color {
        switch self {
        case .overview: return Theme.accent
        case .spatial: return Theme.accentViolet
        case .structure: return Color(red: 0.45, green: 0.82, blue: 0.86)
        case .resources: return Color(red: 1.00, green: 0.72, blue: 0.30)
        case .binary: return Theme.accentWarm
        case .dependencies: return Color(red: 0.52, green: 0.70, blue: 1.00)
        case .signing: return Theme.accentMint
        case .privacy: return Color(red: 0.55, green: 0.88, blue: 0.70)
        case .insights: return Color(red: 1.00, green: 0.80, blue: 0.36)
        case .metadata: return Color(red: 0.70, green: 0.74, blue: 0.86)
        case .anatomy: return Color(red: 0.82, green: 0.62, blue: 0.98)
        }
    }

    var group: String {
        switch self {
        case .overview, .spatial, .insights: return "Explore"
        case .structure, .resources, .metadata: return "Contents"
        case .binary, .dependencies: return "Executable"
        case .signing, .privacy: return "Trust"
        case .anatomy: return "Reference"
        }
    }

    static var groups: [(name: String, items: [ExplorerSection])] {
        let order = ["Explore", "Contents", "Executable", "Trust", "Reference"]
        return order.map { name in
            (name, allCases.filter { $0.group == name })
        }
    }
}

struct SearchHit: Identifiable {
    enum Origin {
        case file(FileNode)
        case library(LinkedLibrary)
        case section(MachOSection)
        case plistKey(String, String)
        case entitlement(String, String)
        case localization(String)
    }

    let id = UUID()
    var title: String
    var subtitle: String
    var symbol: String
    var tint: Color
    var destination: ExplorerSection
    var origin: Origin
}

@MainActor
final class AppState: ObservableObject {

    @Published private(set) var analysis: IPAAnalysis?
    @Published private(set) var progress: AnalysisProgress?
    @Published var errorMessage: String?
    @Published var isDropTargeted = false

    @Published var section: ExplorerSection = .overview
    @Published var selectedFileID: String?
    @Published var spatialMode: SpatialMode = .city
    @Published var autoRotate = false
    @Published var labelMode: SpatialLabelMode = .hover
    @Published var hoveredSpatial: SpatialSelection?
    /// What the user clicked in the 3D scene — drives the detail panel.
    @Published var spatialSelection: SpatialSelection?

    @Published var searchQuery: String = ""
    @Published var isSearchPresented = false
    @Published var resourceFilter: FileKind?
    @Published var resourceQuery: String = ""
    @Published var selectedResourceID: String?

    var isLoading: Bool { progress != nil }

    var selectedFile: FileNode? {
        guard let selectedFileID, let analysis else { return nil }
        return analysis.payloadRoot.flattened().first { $0.relativePath == selectedFileID }
    }

    var selectedResource: FileNode? {
        guard let selectedResourceID, let analysis else { return nil }
        return analysis.payloadRoot.allFiles().first { $0.relativePath == selectedResourceID }
    }

    // MARK: - Loading

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose an iOS application archive"
        panel.prompt = "Inspect"
        if let ipa = UTType(filenameExtension: "ipa") {
            panel.allowedContentTypes = [ipa, .zip]
        }
        if panel.runModal() == .OK, let url = panel.url {
            load(url: url)
        }
    }

    func load(url: URL) {
        guard !isLoading else { return }
        errorMessage = nil
        progress = AnalysisProgress(stage: .reading, fraction: 0)

        let needsScopedAccess = url.startAccessingSecurityScopedResource()

        Task.detached(priority: .userInitiated) {
            do {
                let result = try IPAAnalyzer.analyze(url: url) { update in
                    Task { @MainActor [weak self] in self?.progress = update }
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.applyLoaded(result)
                    if needsScopedAccess { url.stopAccessingSecurityScopedResource() }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.progress = nil
                    self?.errorMessage = error.localizedDescription
                    if needsScopedAccess { url.stopAccessingSecurityScopedResource() }
                }
            }
        }
    }

    private func applyLoaded(_ result: IPAAnalysis) {
        cleanUpPreviousWorkspace(keeping: result.extractionRoot)
        analysis = result
        progress = nil
        section = .overview
        selectedFileID = nil
        selectedResourceID = result.payloadRoot.allFiles()
            .filter { $0.kind == .image }
            .max { $0.size < $1.size }?.relativePath
        resourceFilter = nil
        resourceQuery = ""
        searchQuery = ""
    }

    private var previousWorkspace: URL?

    private func cleanUpPreviousWorkspace(keeping newRoot: URL) {
        if let previousWorkspace, previousWorkspace != newRoot {
            try? FileManager.default.removeItem(at: previousWorkspace)
        }
        previousWorkspace = newRoot
    }

    func close() {
        if let previousWorkspace {
            try? FileManager.default.removeItem(at: previousWorkspace)
        }
        previousWorkspace = nil
        analysis = nil
        selectedFileID = nil
        selectedResourceID = nil
        searchQuery = ""
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url, ["ipa", "zip"].contains(url.pathExtension.lowercased()) else { return }
            Task { @MainActor [weak self] in self?.load(url: url) }
        }
        return true
    }

    // MARK: - Navigation

    /// A click in the 3D scene opens the detail panel rather than jumping away.
    func reveal(spatial selection: SpatialSelection) {
        spatialSelection = spatialSelection == selection ? nil : selection
        if case .file(let path) = selection { selectedFileID = path }
    }

    func focus(on hit: SearchHit) {
        section = hit.destination
        switch hit.origin {
        case .file(let node):
            selectedFileID = node.relativePath
            if hit.destination == .resources { selectedResourceID = node.relativePath }
        default:
            break
        }
        isSearchPresented = false
    }

    // MARK: - Search

    func searchResults(limit: Int = 60) -> [SearchHit] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard query.count >= 2, let analysis else { return [] }
        var hits: [SearchHit] = []

        for file in analysis.payloadRoot.allFiles()
        where file.name.lowercased().contains(query) || file.relativePath.lowercased().contains(query) {
            hits.append(SearchHit(title: file.name,
                                  subtitle: "\(Format.bytes(file.size)) · \(file.relativePath)",
                                  symbol: file.kind.symbol,
                                  tint: file.kind.color,
                                  destination: ResourceViewerSupport.isPreviewable(file) ? .resources : .structure,
                                  origin: .file(file)))
        }

        if let slice = analysis.app.machO?.primarySlice {
            for library in slice.libraries where library.path.lowercased().contains(query) {
                hits.append(SearchHit(title: library.name,
                                      subtitle: "\(library.kind.rawValue) · \(library.path)",
                                      symbol: library.isEmbedded ? "shippingbox.fill" : "cube.transparent.fill",
                                      tint: library.isEmbedded ? FileKind.framework.color : FileKind.dynamicLibrary.color,
                                      destination: .dependencies,
                                      origin: .library(library)))
            }
            for machOSection in slice.allSections where machOSection.name.lowercased().contains(query) {
                hits.append(SearchHit(title: "\(machOSection.segment),\(machOSection.name)",
                                      subtitle: "\(Format.bytes(machOSection.size)) at \(Format.hex(machOSection.address, width: 12))",
                                      symbol: "square.stack.3d.up.fill",
                                      tint: Theme.accentWarm,
                                      destination: .binary,
                                      origin: .section(machOSection)))
            }
        }

        for (key, value) in analysis.app.infoPlist {
            let rendered = String(describing: value)
            guard key.lowercased().contains(query) || rendered.lowercased().contains(query) else { continue }
            hits.append(SearchHit(title: key,
                                  subtitle: rendered.replacingOccurrences(of: "\n", with: " ").prefix(120).description,
                                  symbol: "doc.text.fill",
                                  tint: Color(red: 0.70, green: 0.74, blue: 0.86),
                                  destination: .metadata,
                                  origin: .plistKey(key, rendered)))
        }

        if let entitlements = analysis.app.entitlements {
            for (key, value) in entitlements where key.lowercased().contains(query) {
                hits.append(SearchHit(title: key,
                                      subtitle: String(describing: value),
                                      symbol: "checkmark.seal.fill",
                                      tint: Theme.accentMint,
                                      destination: .signing,
                                      origin: .entitlement(key, String(describing: value))))
            }
        }

        for code in analysis.localizations where code.lowercased().contains(query) {
            hits.append(SearchHit(title: code,
                                  subtitle: Locale.current.localizedString(forIdentifier: code) ?? "Localization",
                                  symbol: "globe",
                                  tint: FileKind.localization.color,
                                  destination: .structure,
                                  origin: .localization(code)))
        }

        // Prefix matches first, then shorter titles — closest match on top.
        return Array(hits.sorted { lhs, rhs in
            let l = lhs.title.lowercased().hasPrefix(query)
            let r = rhs.title.lowercased().hasPrefix(query)
            if l != r { return l }
            return lhs.title.count < rhs.title.count
        }.prefix(limit))
    }
}

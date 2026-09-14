//
//  StructureSection.swift
//  BinaryExplorer
//
//  The bundle tree with a size bar per row, plus an inspector for the
//  selected node and a rollup of the nested bundles.
//

import SwiftUI

struct StructureSection: View {
    let analysis: IPAAnalysis
    @EnvironmentObject private var state: AppState
    @State private var expanded: Set<String> = []
    @State private var filter: String = ""
    @State private var showsOnlyLarge = false

    private var rootNodes: [FileNode] { analysis.payloadRoot.sortedChildren }

    var body: some View {
        HSplitView {
            treePane
                .frame(minWidth: 420, idealWidth: 620)
            inspectorPane
                .frame(minWidth: 320, idealWidth: 380)
        }
        .background(Color.clear)
        .onAppear {
            // Open the app bundle straight away — a single collapsed row is a
            // poor first look at a 191-file payload.
            guard expanded.isEmpty else { return }
            expanded = Set(analysis.payloadRoot.children.map(\.relativePath))
        }
    }

    // MARK: Tree

    private var treePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "Structure",
                             subtitle: "\(Format.count(analysis.payloadRoot.fileCount)) files · \(Format.bytes(analysis.uncompressedSize)) unpacked",
                             symbol: ExplorerSection.structure.symbol,
                             tint: ExplorerSection.structure.tint)
                HStack(spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tertiaryText)
                        TextField("Filter by name", text: $filter)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5))
                        if !filter.isEmpty {
                            Button { filter = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiaryText)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                    Toggle("≥ 100 KB", isOn: $showsOnlyLarge)
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .font(.system(size: 11))
                        .help("Hide every file and folder under 100 KB")

                    Button {
                        expanded = expanded.isEmpty ? Set(analysis.payloadRoot.flattened().map(\.relativePath)) : []
                    } label: {
                        Label(expanded.isEmpty ? "Expand all" : "Collapse all",
                              systemImage: expanded.isEmpty ? "chevron.down.square" : "chevron.right.square")
                    }
                    .controlSize(.small)
                    .font(.system(size: 11))
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Divider().opacity(0.25)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(rootNodes) { node in
                        TreeRowGroup(node: node,
                                     depth: 0,
                                     maximum: Double(analysis.payloadRoot.size),
                                     filter: filter,
                                     minimumSize: showsOnlyLarge ? 100 * 1024 : 0,
                                     expanded: $expanded,
                                     selection: $state.selectedFileID)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: Inspector

    private var inspectorPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let node = state.selectedFile {
                    NodeInspector(node: node, analysis: analysis)
                } else {
                    bundleRollup
                }
            }
            .padding(22)
        }
    }

    private var bundleRollup: some View {
        VStack(alignment: .leading, spacing: 16) {
            NoteBlock(text: "An .ipa is a ZIP whose root holds a single Payload/ folder. Inside it sits the .app bundle: the Mach-O executable, Info.plist, compiled Assets.car, the _CodeSignature manifest, the embedded provisioning profile, plus Frameworks/, PlugIns/ and Watch/ for embedded code.")

            Card(title: "Nested bundles",
                 subtitle: "Every code-bearing bundle inside the payload",
                 symbol: "square.stack.3d.down.right.fill",
                 tint: ExplorerSection.structure.tint) {
                VStack(spacing: 8) {
                    ForEach(analysis.allBundles) { bundle in
                        HStack(spacing: 10) {
                            Image(systemName: bundle.kind.symbol)
                                .font(.system(size: 11))
                                .foregroundStyle(bundle.kind.fileKind.color)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(bundle.name)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(Theme.primaryText)
                                    .lineLimit(1)
                                Text(bundle.kind.rawValue)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            Spacer(minLength: 6)
                            Text(Format.bytes(bundle.size))
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }

            if !analysis.localizations.isEmpty {
                Card(title: "Localizations",
                     subtitle: "\(analysis.localizations.count) .lproj folders across the payload",
                     symbol: "globe",
                     tint: FileKind.localization.color) {
                    FlowLayout(spacing: 6) {
                        ForEach(analysis.localizations, id: \.self) { code in
                            Chip(text: "\(code) · \(Locale.current.localizedString(forIdentifier: code) ?? code)",
                                 tint: FileKind.localization.color)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Tree rows

private struct TreeRowGroup: View {
    let node: FileNode
    let depth: Int
    let maximum: Double
    let filter: String
    let minimumSize: UInt64
    @Binding var expanded: Set<String>
    @Binding var selection: String?

    /// The size floor applies to folders as well as files — a directory's size
    /// is the recursive sum of its children, so anything that still holds a
    /// large file survives the filter and everything smaller disappears.
    private var matches: Bool {
        guard node.size >= minimumSize else { return false }
        return filter.isEmpty
            || node.name.localizedCaseInsensitiveContains(filter)
            || node.flattened().contains { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    private var isExpanded: Bool {
        expanded.contains(node.relativePath) || (!filter.isEmpty && node.isDirectory)
    }

    var body: some View {
        if matches {
            TreeRow(node: node,
                    depth: depth,
                    maximum: maximum,
                    isExpanded: isExpanded,
                    isSelected: selection == node.relativePath,
                    toggle: {
                        if expanded.contains(node.relativePath) {
                            expanded.remove(node.relativePath)
                        } else {
                            expanded.insert(node.relativePath)
                        }
                    },
                    select: { selection = node.relativePath })

            if node.isDirectory, isExpanded {
                ForEach(node.sortedChildren) { child in
                    TreeRowGroup(node: child,
                                 depth: depth + 1,
                                 maximum: maximum,
                                 filter: filter,
                                 minimumSize: minimumSize,
                                 expanded: $expanded,
                                 selection: $selection)
                }
            }
        }
    }
}

private struct TreeRow: View {
    let node: FileNode
    let depth: Int
    let maximum: Double
    let isExpanded: Bool
    let isSelected: Bool
    let toggle: () -> Void
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 7) {
            Color.clear.frame(width: CGFloat(depth) * 15)

            Button(action: toggle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(Theme.tertiaryText)
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .opacity(node.isDirectory && !node.children.isEmpty ? 1 : 0)
            .disabled(!node.isDirectory)

            Image(systemName: node.kind.symbol)
                .font(.system(size: 10.5))
                .foregroundStyle(node.kind.color)
                .frame(width: 16)

            Text(node.name)
                .font(.system(size: 11.5, weight: node.isDirectory ? .medium : .regular))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)

            if node.isDirectory {
                Text("\(node.fileCount)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 4.5).padding(.vertical, 1)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }

            Spacer(minLength: 10)

            GeometryReader { proxy in
                HStack {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(node.kind.color.opacity(isHovering || isSelected ? 0.95 : 0.55))
                        .frame(width: max(2, proxy.size.width * Double(node.size) / max(maximum, 1)),
                               height: 5)
                }
                .frame(height: proxy.size.height, alignment: .center)
            }
            .frame(width: 110, height: 14)

            Text(Format.bytes(node.size))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 74, alignment: .trailing)
        }
        .padding(.vertical, 3.5)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .rowHighlight(isSelected: isSelected, tint: ExplorerSection.structure.tint)
        .background(isHovering && !isSelected
                    ? RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04))
                    : nil)
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { if node.isDirectory { toggle() } else { select() } }
        .onTapGesture { select() }
    }
}

// MARK: - Node inspector

struct NodeInspector: View {
    let node: FileNode
    let analysis: IPAAnalysis
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: node.kind.symbol)
                            .font(.system(size: 17))
                            .foregroundStyle(node.kind.color)
                            .frame(width: 38, height: 38)
                            .background(node.kind.color.opacity(0.14),
                                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(node.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(2)
                            Text(node.kind.title)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        Spacer(minLength: 0)
                    }

                    VStack(spacing: 0) {
                        KeyValueRow(key: "Unpacked size", value: Format.bytes(node.size))
                        if !node.isDirectory {
                            KeyValueRow(key: "Compressed", value: Format.bytes(node.compressedSize))
                            KeyValueRow(key: "Compression",
                                        value: node.compressedSize >= node.size
                                            ? "Stored"
                                            : String(format: "%.0f%% of original",
                                                     Double(node.compressedSize) / Double(max(node.size, 1)) * 100))
                        } else {
                            KeyValueRow(key: "Contains", value: "\(Format.count(node.fileCount)) files")
                        }
                        KeyValueRow(key: "Share of payload",
                                    value: String(format: "%.2f%%",
                                                  Double(node.size) / Double(max(analysis.uncompressedSize, 1)) * 100))
                        KeyValueRow(key: "Path", value: node.relativePath, monospaced: true)
                    }

                    NoteBlock(text: node.kind.explanation, symbol: node.kind.symbol, tint: node.kind.color)

                    if !node.isDirectory {
                        Button {
                            state.selectedResourceID = node.relativePath
                            state.section = .resources
                        } label: {
                            Label("Open in resource viewer", systemImage: "eye.fill")
                                .font(.system(size: 11.5, weight: .medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ExplorerSection.resources.tint)
                        .controlSize(.regular)
                    }
                }
            }

            if node.isDirectory, !node.children.isEmpty {
                Card(title: "Breakdown", symbol: "chart.bar.fill", tint: node.kind.color) {
                    let children = Array(node.sortedChildren.prefix(10))
                    let maximum = Double(children.first?.size ?? 1)
                    VStack(spacing: 9) {
                        ForEach(children) { child in
                            FileBar(file: child, maximum: maximum)
                        }
                    }
                }
            }
        }
    }
}

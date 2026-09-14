//
//  ResourcesSection.swift
//  BinaryExplorer
//
//  Browse and preview every resource in the payload: thumbnail grid on the
//  left, live preview on the right.
//

import SwiftUI

struct ResourcesSection: View {
    let analysis: IPAAnalysis
    @EnvironmentObject private var state: AppState
    @State private var layout: Layout = .grid

    enum Layout: String, CaseIterable {
        case grid = "Grid", list = "List"
        var symbol: String { self == .grid ? "square.grid.2x2" : "list.bullet" }
    }

    private var allFiles: [FileNode] { analysis.payloadRoot.allFiles() }

    private var availableKinds: [FileKind] {
        let counts = Dictionary(grouping: allFiles, by: \.kind)
        return counts.keys.sorted { lhs, rhs in
            (counts[lhs]?.count ?? 0) > (counts[rhs]?.count ?? 0)
        }
    }

    private var filtered: [FileNode] {
        let query = state.resourceQuery.trimmingCharacters(in: .whitespaces).lowercased()
        return allFiles.filter { file in
            (state.resourceFilter == nil || file.kind == state.resourceFilter)
                && (query.isEmpty
                    || file.name.lowercased().contains(query)
                    || file.relativePath.lowercased().contains(query))
        }
        .sorted { $0.size > $1.size }
    }

    var body: some View {
        HSplitView {
            browser
                .frame(minWidth: 420, idealWidth: 560)
            previewPane
                .frame(minWidth: 400, idealWidth: 520)
        }
    }

    // MARK: Browser

    private var browser: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "Resources",
                             subtitle: "\(Format.count(filtered.count)) of \(Format.count(allFiles.count)) files",
                             symbol: ExplorerSection.resources.symbol,
                             tint: ExplorerSection.resources.tint)

                HStack(spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 10)).foregroundStyle(Theme.tertiaryText)
                        TextField("Search resources", text: $state.resourceQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5))
                        if !state.resourceQuery.isEmpty {
                            Button { state.resourceQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.tertiaryText)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                    Picker("", selection: $layout) {
                        ForEach(Layout.allCases, id: \.self) { option in
                            Image(systemName: option.symbol).tag(option)
                        }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 74)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        FilterChip(title: "All",
                                   symbol: "square.grid.3x3.fill",
                                   tint: Theme.accent,
                                   count: allFiles.count,
                                   isActive: state.resourceFilter == nil) {
                            state.resourceFilter = nil
                        }
                        ForEach(availableKinds) { kind in
                            let count = allFiles.filter { $0.kind == kind }.count
                            FilterChip(title: kind.title,
                                       symbol: kind.symbol,
                                       tint: kind.color,
                                       count: count,
                                       isActive: state.resourceFilter == kind) {
                                state.resourceFilter = state.resourceFilter == kind ? nil : kind
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Divider().opacity(0.25)

            if filtered.isEmpty {
                ContentUnavailableLabel(symbol: "tray",
                                        title: "Nothing here",
                                        message: "No resource matches the current filter.")
                .frame(maxHeight: .infinity)
            } else if layout == .grid {
                gridView
            } else {
                listView
            }
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 12)], spacing: 12) {
                ForEach(filtered) { file in
                    ResourceTile(file: file, isSelected: state.selectedResourceID == file.relativePath)
                        .onTapGesture { state.selectedResourceID = file.relativePath }
                }
            }
            .padding(18)
        }
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(filtered) { file in
                    HStack(spacing: 10) {
                        ResourceThumbnail(file: file, side: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.name)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(1)
                            Text(file.relativePath)
                                .font(.system(size: 9.5))
                                .foregroundStyle(Theme.tertiaryText)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Text(file.kind.title)
                            .font(.system(size: 9.5))
                            .foregroundStyle(file.kind.color)
                        Text(Format.bytes(file.size))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 72, alignment: .trailing)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .rowHighlight(isSelected: state.selectedResourceID == file.relativePath,
                                  tint: ExplorerSection.resources.tint)
                    .onTapGesture { state.selectedResourceID = file.relativePath }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    // MARK: Preview

    private var previewPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let file = state.selectedResource {
                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                Image(systemName: file.kind.symbol)
                                    .font(.system(size: 15))
                                    .foregroundStyle(file.kind.color)
                                    .frame(width: 34, height: 34)
                                    .background(file.kind.color.opacity(0.14),
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundStyle(Theme.primaryText)
                                        .lineLimit(1)
                                    Text("\(file.kind.title) · \(Format.bytes(file.size))")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Theme.tertiaryText)
                                }
                                Spacer(minLength: 0)
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([file.url])
                                } label: {
                                    Image(systemName: "arrow.up.forward.app")
                                }
                                .buttonStyle(.borderless)
                                .help("Reveal the unpacked file in Finder")
                            }
                            Text(file.relativePath)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.tertiaryText)
                                .textSelection(.enabled)

                            Divider().opacity(0.2)

                            ResourcePreview(node: file)
                        }
                    }
                } else {
                    ContentUnavailableLabel(symbol: "eye.slash",
                                            title: "No resource selected",
                                            message: "Pick a file on the left to preview it.")
                }
            }
            .padding(22)
        }
    }
}

// MARK: - Pieces

private struct FilterChip: View {
    let title: String
    let symbol: String
    let tint: Color
    let count: Int
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                Text(title).font(.system(size: 10.5, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 9, design: .monospaced))
                    .opacity(0.7)
            }
            .foregroundStyle(isActive ? Color.black.opacity(0.85) : tint)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(isActive ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.13))))
            .overlay(Capsule().strokeBorder(tint.opacity(isActive ? 0 : 0.28), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ResourceThumbnail: View {
    let file: FileNode
    var side: CGFloat = 64

    private var image: NSImage? {
        guard file.kind == .image || file.kind == .vector else { return nil }
        // Thumbnail at a bounded size so a 4K PNG doesn't stall the grid.
        guard let source = CGImageSourceCreateWithURL(file.url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(side * 3),
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: file.kind.symbol)
                    .font(.system(size: side * 0.38, weight: .light))
                    .foregroundStyle(file.kind.color)
            }
        }
        .frame(width: side, height: side)
    }
}

private struct ResourceTile: View {
    let file: FileNode
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.black.opacity(0.28))
                ResourceThumbnail(file: file, side: 70)
                    .padding(6)
            }
            .frame(height: 86)

            VStack(spacing: 2) {
                Text(file.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Format.bytes(file.size))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? ExplorerSection.resources.tint.opacity(0.16) : Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? ExplorerSection.resources.tint.opacity(0.6) : Theme.cardStroke,
                              lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}
